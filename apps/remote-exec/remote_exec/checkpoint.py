"""Publish a filtered verified export as a private standard-Git checkpoint.

The checkpoint is built from the capture's `work/` tree, not from the caller's
working tree: blobs are written with `hash-object --no-filters`, trees with
`mktree -z`, and one commit with `commit-tree`. Nothing touches HEAD, the
index, user branches or working bytes. Every Git invocation disables hooks and
commit signing, so no reference-transaction hook or external gpg program runs.

A default checkpoint id is a fresh UUID: two consumers of the same input get
independent refs. An explicit id is a logical consumer/retry id; replay is
accepted only when the existing commit's tree, parents and input-id metadata
all match this capture.
"""

from __future__ import annotations

import os
import re
import subprocess
import uuid

from . import manifest

REF_NAMESPACE = "refs/remote-exec/checkpoints/"
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
IDENTITY_PATTERN = re.compile(r"^(.*?) <(.+)> \d+ [+-]\d{4}$")
INPUT_TRAILER = "Remote-Exec-Input-Id: "


class CheckpointError(Exception):
    pass


def _git(repo: str, args: list[str], stdin: bytes | None = None, env: dict | None = None) -> bytes:
    environment = dict(os.environ)
    environment.update(
        {
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "LC_ALL": "C",
        }
    )
    environment.update(env or {})
    # Hooks and signing are disabled on every mutation, not only blob writing.
    command = [
        "git",
        "-C",
        repo,
        "-c",
        "core.hooksPath=/nonexistent",
        "-c",
        "commit.gpgSign=false",
        "-c",
        "tag.gpgSign=false",
        *args,
    ]
    process = subprocess.run(
        command,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        check=False,
    )
    if process.returncode != 0:
        raise CheckpointError(
            f"git {' '.join(args)} failed: "
            + process.stderr.decode("utf-8", "replace").strip()
        )
    return process.stdout


def _identity(repo: str, author_name: str | None, author_email: str | None) -> tuple[str, str]:
    if author_name and author_email:
        return author_name, author_email
    if author_name or author_email:
        raise CheckpointError("declare both author name and author email, or neither")
    for variable in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
        try:
            value = _git(repo, ["var", variable]).decode("utf-8", "replace").strip()
        except CheckpointError:
            continue
        match = IDENTITY_PATTERN.match(value)
        if match:
            return match.group(1), match.group(2)
    raise CheckpointError(
        "no caller Git identity is declared; set user.name/user.email in the repository "
        "or pass --author-name and --author-email (this command never writes config)"
    )


def _write_blob(repo: str, content: bytes) -> str:
    # --no-filters is the production guarantee: exact bytes, no clean filter.
    return _git(repo, ["hash-object", "-w", "--no-filters", "--stdin"], stdin=content).decode().strip()


def _tree(repo: str, root: str, entries: list[dict]) -> str:
    """Build nested trees from the manifest entries under `root`."""
    directories: dict[str, dict] = {"": {}}
    for entry in entries:
        rel = entry["path"]
        parent = os.path.dirname(rel)
        directories.setdefault(parent, {})[os.path.basename(rel)] = entry
        while parent:
            parent = os.path.dirname(parent)
            directories.setdefault(parent, {})

    def build(prefix: str) -> str:
        records: list[tuple[bytes, bytes]] = []
        for name, entry in sorted(directories.get(prefix, {}).items()):
            rel = f"{prefix}/{name}" if prefix else name
            if entry["type"] == "symlink":
                blob = _write_blob(repo, os.fsencode(entry["target"]))
                mode, kind = b"120000", b"blob"
            else:
                with open(os.path.join(root, rel), "rb") as handle:
                    blob = _write_blob(repo, handle.read())
                mode = b"100755" if entry["mode"] == manifest.EXEC_MODE else b"100644"
                kind = b"blob"
            records.append(
                (
                    os.fsencode(name),
                    mode + b" " + kind + b" " + blob.encode() + b"\t" + os.fsencode(name) + b"\0",
                )
            )
        for name in sorted(directories):
            if name == prefix or os.path.dirname(name) != prefix or name == "":
                continue
            child = build(name)
            records.append(
                (
                    os.fsencode(os.path.basename(name)),
                    b"040000 tree " + child.encode() + b"\t" + os.fsencode(os.path.basename(name)) + b"\0",
                )
            )
        records.sort(key=lambda item: item[0])
        return _git(repo, ["mktree", "-z"], stdin=b"".join(record for _, record in records)).decode().strip()

    return build("")


def _commit_message(parent: str | None, input_id: str) -> bytes:
    lines = ["remote-exec checkpoint", "", f"Parent-Revision: {parent or 'none'}", INPUT_TRAILER + input_id]
    return ("\n".join(lines) + "\n").encode()


def _ref_for(checkpoint_id: str) -> str:
    if not ID_PATTERN.match(checkpoint_id or "") or ".." in checkpoint_id:
        raise CheckpointError(f"checkpoint id {checkpoint_id!r} is not a safe ref component")
    return REF_NAMESPACE + checkpoint_id


def _ref_commit(repo: str, ref: str) -> str | None:
    process = subprocess.run(
        ["git", "-C", repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=dict(os.environ, GIT_CONFIG_NOSYSTEM="1"),
        check=False,
    )
    if process.returncode != 0:
        return None
    return process.stdout.decode().strip()


def _commit_input_id(repo: str, commit: str) -> str | None:
    body = _git(repo, ["cat-file", "commit", commit]).decode("utf-8", "replace")
    for line in body.splitlines():
        if line.startswith(INPUT_TRAILER):
            return line[len(INPUT_TRAILER) :].strip()
    return None


def _commit_parents(repo: str, commit: str) -> list[str]:
    fields = _git(repo, ["rev-list", "--parents", "-n", "1", commit]).decode().strip().split()
    return fields[1:]


def _matches(repo: str, commit: str, tree: str, parent: str | None, input_id: str) -> bool:
    actual_tree = _git(repo, ["rev-parse", commit + "^{tree}"]).decode().strip()
    parents = _commit_parents(repo, commit)
    expected_parents = [parent] if parent else []
    return (
        actual_tree == tree
        and parents == expected_parents
        and _commit_input_id(repo, commit) == input_id
    )


def create(
    repo: str,
    capture_dir: str,
    checkpoint_id: str | None = None,
    author_name: str | None = None,
    author_email: str | None = None,
) -> dict:
    """Publish `capture_dir/work` as a private checkpoint commit and ref."""
    input_files = os.path.join(capture_dir, "input-files.json")
    value = manifest.load_manifest(input_files)
    work = os.path.join(capture_dir, "work")
    manifest.verify(work, input_files, value["inputId"])

    repo = os.path.realpath(repo)
    # The captured base is provenance. Never use the repository's current HEAD,
    # which may have advanced since capture.
    parent = value.get("baseRevision")
    if parent:
        _git(repo, ["cat-file", "-e", parent + "^{commit}"])
    checkpoint_id = checkpoint_id or str(uuid.uuid4())
    ref = _ref_for(checkpoint_id)
    tree = _tree(repo, work, value["files"])

    existing = _ref_commit(repo, ref)
    if existing is not None:
        if _matches(repo, existing, tree, parent, value["inputId"]):
            return {
                "sourceRoot": repo,
                "parentRevision": parent,
                "inputId": value["inputId"],
                "checkpoint": {
                    "id": checkpoint_id,
                    "commit": existing,
                    "tree": tree,
                    "ref": ref,
                },
                "replayed": True,
            }
        raise CheckpointError(
            f"checkpoint {checkpoint_id!r} already names a different tree, parent or input; "
            "choose another id"
        )

    name, email = _identity(repo, author_name, author_email)
    env = {
        "GIT_AUTHOR_NAME": name,
        "GIT_AUTHOR_EMAIL": email,
        "GIT_COMMITTER_NAME": name,
        "GIT_COMMITTER_EMAIL": email,
    }
    arguments = ["commit-tree", tree]
    if parent:
        arguments += ["-p", parent]
    commit = _git(repo, arguments, stdin=_commit_message(parent, value["inputId"]), env=env).decode().strip()

    zero = "0" * 40
    try:
        _git(repo, ["update-ref", ref, commit, zero])
    except CheckpointError:
        # A concurrent creator may have won; accept only a fully matching receipt.
        winner = _ref_commit(repo, ref)
        if winner is None or not _matches(repo, winner, tree, parent, value["inputId"]):
            raise
        commit = winner
    return {
        "sourceRoot": repo,
        "parentRevision": parent,
        "inputId": value["inputId"],
        "checkpoint": {"id": checkpoint_id, "commit": commit, "tree": tree, "ref": ref},
        "replayed": False,
    }


def release(repo: str, ref: str, expected_commit: str) -> dict:
    """Delete an owned checkpoint ref with an expected-commit CAS."""
    if not ref.startswith(REF_NAMESPACE):
        raise CheckpointError(f"ref {ref!r} is outside the owned checkpoint namespace")
    checkpoint_id = ref[len(REF_NAMESPACE) :]
    _ref_for(checkpoint_id)
    repo = os.path.realpath(repo)
    current = _ref_commit(repo, ref)
    if current is None:
        return {"ref": ref, "released": False, "reason": "already absent"}
    if current != expected_commit:
        raise CheckpointError(
            f"ref {ref} points at {current}, not the expected {expected_commit}; refusing to release"
        )
    _git(repo, ["update-ref", "-d", ref, expected_commit])
    return {"ref": ref, "released": True, "commit": expected_commit}
