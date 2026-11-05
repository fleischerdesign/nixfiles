"""Canonical file manifests for a remote-exec input.

The manifest is the identity of an attempt's input: it lists every regular file
and symlink by relative path, type, mode and content digest (or link target).
`inputId` is a SHA-256 over the canonical JSON, so it can be computed on the
Gateway and again on the executor and compared byte for byte.

Only data that can be reproduced by copying is represented. Directories carry
no input identity: Git tracks files, and an empty directory changes no build.
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
from typing import Iterable

SCHEMA_VERSION = 1

FILE_MODE = "100644"
EXEC_MODE = "100755"
LINK_MODE = "120000"


class ManifestError(Exception):
    """The input cannot be represented or does not verify."""


def canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def input_id(files: Iterable[dict]) -> str:
    payload = {"schemaVersion": SCHEMA_VERSION, "files": list(files)}
    return hashlib.sha256(canonical_bytes(payload)).hexdigest()


def validate_relpath(rel: str) -> str:
    """Reject anything that could escape the export root.

    Git writes repository-relative paths with `/` separators. Absolute paths,
    empty components, `.`/`..` and any `.git` component are refused rather than
    normalised: a silently rewritten path changes the input.
    """
    if not isinstance(rel, str) or rel == "":
        raise ManifestError("empty path in input")
    if rel.startswith("/") or "\\" in rel:
        raise ManifestError(f"unsafe path {rel!r}: not a relative slash path")
    parts = rel.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ManifestError(f"unsafe path {rel!r}: empty, '.' or '..' component")
    if ".git" in parts:
        raise ManifestError(f"unsafe path {rel!r}: .git is never source")
    return rel


def validate_symlink(rel: str, target: str) -> str:
    """A symlink must stay inside the export root when resolved lexically."""
    if not isinstance(target, str) or target == "":
        raise ManifestError(f"symlink {rel!r} has an empty target")
    if os.path.isabs(target):
        raise ManifestError(f"symlink {rel!r} points outside the input: {target!r}")
    parent = os.path.dirname(rel)
    resolved = os.path.normpath(os.path.join(parent, target))
    if resolved == ".." or resolved.startswith("../"):
        raise ManifestError(f"symlink {rel!r} escapes the input: {target!r}")
    return target


def _hash_file(path: str) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        while True:
            block = handle.read(1 << 20)
            if not block:
                break
            digest.update(block)
            size += len(block)
    return size, digest.hexdigest()


def describe(root: str, rel: str) -> dict:
    """Describe one path under `root` as a manifest entry."""
    validate_relpath(rel)
    path = os.path.join(root, rel)
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode):
        target = validate_symlink(rel, os.readlink(path))
        return {"path": rel, "type": "symlink", "mode": LINK_MODE, "target": target}
    if stat.S_ISREG(info.st_mode):
        size, digest = _hash_file(path)
        mode = EXEC_MODE if info.st_mode & 0o111 else FILE_MODE
        return {
            "path": rel,
            "type": "file",
            "mode": mode,
            "size": size,
            "sha256": digest,
        }
    raise ManifestError(f"unsupported file type at {rel!r}: only files and symlinks are source")


def tree_entries(root: str) -> dict[str, dict]:
    """Every file and symlink under `root`, keyed by relative path.

    `.git` entries are refused instead of skipped: their presence means the
    export contract was bypassed.
    """
    entries: dict[str, dict] = {}
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in list(dirnames):
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                dirnames.remove(name)
                rel = os.path.relpath(full, root).replace(os.sep, "/")
                entries[rel] = describe(root, rel)
            elif name == ".git":
                raise ManifestError(f".git directory present in input at {full!r}")
        for name in filenames:
            if name == ".git":
                raise ManifestError("a .git entry is never source")
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            entries[rel] = describe(root, rel)
    return entries


def build_manifest(root: str, base_revision: str | None) -> dict:
    entries = tree_entries(root)
    files = [entries[path] for path in sorted(entries)]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "baseRevision": base_revision,
        "inputId": input_id(files),
        "files": files,
    }


def load_manifest(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read manifest {path}: {error}") from error
    if value.get("schemaVersion") != SCHEMA_VERSION:
        raise ManifestError(f"unsupported manifest schema in {path}")
    files = value.get("files")
    if not isinstance(files, list):
        raise ManifestError(f"manifest {path} has no file list")
    if input_id(files) != value.get("inputId"):
        raise ManifestError(f"manifest {path} digest does not match its entries")
    return value


def verify(root: str, manifest_path: str, expected_input_id: str | None = None) -> str:
    """Recompute the manifest under `root` and compare it with the file.

    Returns the verified inputId; raises ManifestError on any difference,
    including an extra file that the manifest does not list.
    """
    manifest = load_manifest(manifest_path)
    expected = {entry["path"]: entry for entry in manifest["files"]}
    observed = tree_entries(root)
    missing = sorted(set(expected) - set(observed))
    extra = sorted(set(observed) - set(expected))
    changed = sorted(
        path for path in set(expected) & set(observed) if expected[path] != observed[path]
    )
    if missing or extra or changed:
        detail = []
        if missing:
            detail.append(f"missing={missing[:5]}")
        if extra:
            detail.append(f"unexpected={extra[:5]}")
        if changed:
            detail.append(f"changed={changed[:5]}")
        raise ManifestError("input verification failed: " + ", ".join(detail))
    if expected_input_id is not None and expected_input_id != manifest["inputId"]:
        raise ManifestError(
            f"input id mismatch: expected {expected_input_id}, manifest has {manifest['inputId']}"
        )
    return manifest["inputId"]
