"""Source selection and capture from a live Git working tree.

Git decides which paths are source. Tracked paths are always exported (even
when a project ignore rule matches them), untracked paths are exported when the
project's own `.gitignore` files admit them, and a tracked path absent from the
working tree is a deletion.

Personal configuration must not change the input: the untracked query uses
`--exclude-per-directory=.gitignore` and a neutral `core.excludesFile`, so
`~/.config/git/ignore` and `.git/info/exclude` are not consulted.

The caller owns the worktree for the capture window. The capture detects
changes instead of claiming atomicity: it compares the selected path set,
HEAD, the index and every captured file's digest before it publishes a
manifest. A second writer during that window fails the capture.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile

from . import boundary, manifest

GIT_ENV = {
    "GIT_TERMINAL_PROMPT": "0",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_OPTIONAL_LOCKS": "0",
    "LC_ALL": "C",
}

class SourceError(Exception):
    """The working tree cannot be exported as declared input."""


def git(repo: str, *args: str) -> bytes:
    env = dict(os.environ)
    env.update(GIT_ENV)
    process = subprocess.run(
        ["git", "-C", repo, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if process.returncode != 0:
        raise SourceError(
            f"git {' '.join(args)} failed in {repo}: "
            f"{process.stderr.decode('utf-8', 'replace').strip()}"
        )
    return process.stdout


forbidden_reason = boundary.forbidden_reason


def _nul_paths(output: bytes) -> list[str]:
    text = output.decode("utf-8", "surrogateescape")
    return [name for name in text.split("\0") if name]


def _repo_root(repo: str) -> str:
    return os.path.realpath(git(repo, "rev-parse", "--show-toplevel").decode().strip())


def _index_signature(repo: str) -> tuple[int, int, int]:
    index = git(repo, "rev-parse", "--git-path", "index").decode().strip()
    index = index if os.path.isabs(index) else os.path.join(repo, index)
    try:
        info = os.lstat(index)
    except FileNotFoundError:
        return (-1, -1, -1)
    return (info.st_ino, info.st_size, info.st_mtime_ns)


def repo_identity(repo: str) -> str:
    """Identity of the real repository, not of a caller-supplied label.

    The canonical Git common directory distinguishes repositories and is shared
    by linked worktrees of one repository. It is hashed and never shipped: the
    executor receives only the key, never Git metadata or credentials.
    """
    common = git(repo, "rev-parse", "--git-common-dir").decode("utf-8").strip()
    if not os.path.isabs(common):
        common = os.path.join(repo, common)
    common = os.path.realpath(common)
    if not os.path.isdir(common):
        raise SourceError(f"repository common directory {common!r} is not a directory")
    return hashlib.sha256(common.encode("utf-8", "surrogateescape")).hexdigest()


def _gitlinks(repo: str) -> list[str]:
    output = git(repo, "ls-files", "-s", "-z")
    links = []
    for record in output.split(b"\0"):
        if not record:
            continue
        header, _, path = record.partition(b"\t")
        mode = header.split(b" ")[0]
        if mode == b"160000":
            links.append(path.decode("utf-8", "surrogateescape"))
    return links


def _lfs_tracked(repo: str, tracked: list[str]) -> list[str]:
    """Detect Git LFS filter rules in tracked attribute files.

    A pointer file is not the content a build needs, so an LFS-managed project
    is refused rather than exported incorrectly. `git lfs` itself is not
    required for the check.
    """
    found = []
    for rel in tracked:
        if not rel.endswith(".gitattributes"):
            continue
        path = os.path.join(repo, rel)
        try:
            with open(path, "rb") as handle:
                if b"filter=lfs" in handle.read():
                    found.append(rel)
        except OSError:
            continue
    return found


def selected_paths(repo: str) -> list[str]:
    tracked = _nul_paths(git(repo, "ls-files", "-z", "--cached"))
    untracked = _nul_paths(
        git(
            repo,
            "-c",
            "core.excludesFile=/dev/null",
            "ls-files",
            "-z",
            "--others",
            "--exclude-per-directory=.gitignore",
        )
    )
    selected = sorted(set(tracked) | set(untracked))
    for rel in selected:
        try:
            manifest.validate_relpath(rel)
            rel.encode("utf-8")
        except UnicodeEncodeError as error:
            raise SourceError(f"path {rel!r} is not valid UTF-8; refusing an ambiguous input") from error
        except manifest.ManifestError as error:
            raise SourceError(str(error)) from error
        reason = forbidden_reason(rel)
        if reason:
            raise SourceError(
                f"{rel!r} is a {reason}; credential and agent-state paths are never source"
            )
    return selected


def _copy_file(repo: str, rel: str, work: str, after_read=None) -> dict:
    source = os.path.join(repo, rel)
    before = os.lstat(source)
    destination = os.path.join(work, rel)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    digest = hashlib.sha256()
    size = 0
    with open(source, "rb") as reader, open(destination, "wb") as writer:
        while True:
            block = reader.read(1 << 20)
            if not block:
                break
            writer.write(block)
            digest.update(block)
            size += len(block)
    if after_read is not None:
        # Test seam: proves the stability fence fails closed, not silently.
        after_read(rel)
    after = os.lstat(source)
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (
        after.st_size,
        after.st_mtime_ns,
        after.st_ino,
    ):
        raise SourceError(
            f"{rel} changed while it was captured; stop writers in the worktree and retry"
        )
    mode = 0o755 if before.st_mode & 0o111 else 0o644
    os.chmod(destination, mode)
    os.utime(destination, ns=(before.st_atime_ns, before.st_mtime_ns))
    return {
        "path": rel,
        "type": "file",
        "mode": manifest.EXEC_MODE if mode == 0o755 else manifest.FILE_MODE,
        "size": size,
        "sha256": digest.hexdigest(),
    }


def _copy_symlink(repo: str, rel: str, work: str) -> dict:
    target = os.readlink(os.path.join(repo, rel))
    try:
        target = manifest.validate_symlink(rel, target)
    except manifest.ManifestError as error:
        raise SourceError(str(error)) from error
    destination = os.path.join(work, rel)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    os.symlink(target, destination)
    return {"path": rel, "type": "symlink", "mode": manifest.LINK_MODE, "target": target}


def capture(
    repo: str,
    out: str,
    extra_paths: tuple[str, ...] = (),
    *,
    _after_read=None,
    _after_copy=None,
) -> dict:
    """Export the working tree into `out/work` and write `out/input-files.json`.

    `out` must be new or empty. `extra_paths` are explicitly scoped inputs that
    Git ignores (a generated file the repository's own build would produce on
    the executor is preferable); each must exist and pass the same safety and
    credential checks.
    """
    repo = os.path.realpath(repo)
    if _repo_root(repo) != repo:
        raise SourceError(f"{repo} is not the root of a Git working tree")
    if os.path.exists(out) and os.listdir(out):
        raise SourceError(f"capture target {out} is not empty")

    head_before = git(repo, "rev-parse", "HEAD").decode().strip()
    index_before = _index_signature(repo)
    selected_before = selected_paths(repo)

    gitlinks = _gitlinks(repo)
    if gitlinks:
        raise SourceError(
            "submodules are not supported: "
            + ", ".join(gitlinks[:5])
            + " (materialise their content or remove the gitlink)"
        )
    lfs = _lfs_tracked(repo, selected_before)
    if lfs:
        raise SourceError(
            "Git LFS attributes are not supported (pointer files are not source): "
            + ", ".join(lfs[:5])
        )

    selected = list(selected_before)
    for rel in extra_paths:
        manifest.validate_relpath(rel)
        reason = forbidden_reason(rel)
        if reason:
            raise SourceError(f"explicit input {rel} is a {reason}; refusing to export it")
        if not os.path.lexists(os.path.join(repo, rel)):
            raise SourceError(f"explicit input {rel} does not exist")
        if rel not in selected:
            selected.append(rel)
    selected = sorted(set(selected))

    work = os.path.join(out, "work")
    os.makedirs(work, exist_ok=True)
    presence_before = {rel: os.path.lexists(os.path.join(repo, rel)) for rel in selected}
    entries = []
    for rel in selected:
        source = os.path.join(repo, rel)
        try:
            info = os.lstat(source)
        except FileNotFoundError:
            # A tracked path missing from the working tree is a deletion.
            continue
        if stat.S_ISLNK(info.st_mode):
            entries.append(_copy_symlink(repo, rel, work))
        elif stat.S_ISREG(info.st_mode):
            entries.append(_copy_file(repo, rel, work, _after_read))
        else:
            raise SourceError(f"unsupported file type at {rel!r}; only files and symlinks are source")
        if _after_copy is not None:
            _after_copy(rel)

    # The selection itself can change while bytes are copied: a new untracked
    # path, a removed one, a newly ignored one. Compare the whole selection;
    # explicit extras are not part of Git's selection, so re-add them.
    selected_after = selected_paths(repo)
    for rel in extra_paths:
        if os.path.lexists(os.path.join(repo, rel)) and rel not in selected_after:
            selected_after.append(rel)
    selected_after = sorted(set(selected_after))
    if selected != selected_after:
        added = sorted(set(selected_after) - set(selected))
        removed = sorted(set(selected) - set(selected_after))
        raise SourceError(
            "the selected source changed during capture: "
            f"added={added[:5]} removed={removed[:5]}; stop writers and retry"
        )

    head_after = git(repo, "rev-parse", "HEAD").decode().strip()
    index_after = _index_signature(repo)
    if head_before != head_after:
        raise SourceError("HEAD moved during capture; the worktree is not quiescent")
    if index_before != index_after:
        raise SourceError("the Git index changed during capture; the worktree is not quiescent")

    # Re-read every captured path after the copy loop: a file that was already
    # copied when a writer touched it must fail too, not just a file read early.
    captured = {entry["path"]: entry for entry in entries}
    for rel in sorted(captured):
        try:
            current = manifest.describe(repo, rel)
        except FileNotFoundError as error:
            raise SourceError(f"{rel} disappeared during capture; stop writers and retry") from error
        except manifest.ManifestError as error:
            raise SourceError(str(error)) from error
        if current != captured[rel]:
            raise SourceError(
                f"{rel} changed after it was copied; stop writers in the worktree and retry"
            )
    for rel in sorted(set(selected) - set(captured)):
        if os.path.lexists(os.path.join(repo, rel)):
            raise SourceError(f"{rel} appeared during capture; stop writers and retry")
    for rel, present in presence_before.items():
        if os.path.lexists(os.path.join(repo, rel)) != present:
            raise SourceError(f"{rel} changed presence during capture; stop writers and retry")

    files = sorted(entries, key=lambda entry: entry["path"])
    value = {
        "schemaVersion": manifest.SCHEMA_VERSION,
        "baseRevision": head_before,
        "inputId": manifest.input_id(files),
        "files": files,
    }
    manifest.write_manifest(value, os.path.join(out, "input-files.json"))
    return value


def selection_delta(base_manifest: dict, files: list[dict], removed: list[str], attempt_id: str) -> dict:
    """Changes in the selected output relative to the attempt's base input."""
    expected = {entry["path"]: entry for entry in base_manifest["files"]}
    observed = {entry["path"]: entry for entry in files}
    changes = []
    for path in sorted(set(expected) | set(observed) | set(removed)):
        if path in removed or path not in observed:
            changes.append({"path": path, "change": "deleted"})
        elif path not in expected:
            changes.append({"path": path, "change": "added", **observed[path]})
        elif observed[path] != expected[path]:
            changes.append({"path": path, "change": "modified", **observed[path]})
    return {
        "schemaVersion": manifest.SCHEMA_VERSION,
        "attemptId": attempt_id,
        "baseInputId": base_manifest["inputId"],
        "changes": changes,
    }
