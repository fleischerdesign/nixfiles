"""Executor-side scripts for reusable task workspaces.

A workspace is a persistent task directory owned by one executor account:

    <root>/workspaces/<key>/
        workspace.json          identity, label and binding metadata
        state/lease.json        who owns the workspace and in which phase
        state/managed.json      expected state of every managed source path
        state/synced.json       last successfully synced input
        state/update-incomplete.json   present while a sync may be partial
        state/lock              flock: serialises workspace transitions
        work/                   the persistent task workspace (not hermetic)
        home/                   stable HOME for tool-native state
        staging/<attempt-id>/   incoming capture (never inside work/)
        attempts/<attempt-id>/  per-attempt receipts, logs, artifacts, snapshot

The lease is the authority for exclusive ownership. A sync or execution that
dies leaves a non-terminal lease (or an incomplete marker) that fails closed:
the next caller reconciles with `workspace-status`, cancels, or resets instead
of taking over a workspace that may still be written by a live process.
"""

from __future__ import annotations

PRELUDE = r'''
import base64, errno, fcntl, hashlib, json, os, shutil, stat, subprocess, sys, time

CONFIG = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))


def fail(message, code=2):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def atomic_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + ".tmp.%d.%s" % (os.getpid(), os.urandom(6).hex())
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)
    try:
        directory = os.open(os.path.dirname(path) or ".", os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except OSError:
        pass


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def load_module(name, path):
    import importlib.util

    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def lock(path, timeout=60.0):
    handle = open(path, "a+b")
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except BlockingIOError:
            if time.monotonic() >= deadline:
                fail("workspace state lock is held by another operation; retry shortly")
            time.sleep(0.2)


def unlock(handle):
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    finally:
        handle.close()


def workspace_lock_path(workspace):
    """Lock living beside the workspace so retirement and creation serialise."""
    parent = os.path.dirname(os.path.abspath(workspace))
    name = os.path.basename(os.path.abspath(workspace))
    locks = os.path.join(parent, ".locks")
    if os.path.islink(locks):
        fail("refusing a symlinked workspace lock directory: %s" % locks)
    os.makedirs(locks, mode=0o700, exist_ok=True)
    if not os.path.isdir(locks) or os.path.islink(locks):
        fail("workspace lock directory %s is not a real directory" % locks)
    return os.path.join(locks, name + ".lock")


def assert_real_dir(path, label):
    """A workspace-owned path must itself be a directory, not a symlink."""
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        fail("%s is missing: %s" % (label, path))
    if stat.S_ISLNK(info.st_mode):
        fail("%s is a symlink; refusing to use it: %s" % (label, path))
    if not stat.S_ISDIR(info.st_mode):
        fail("%s is not a directory: %s" % (label, path))


def ensure_dir(path):
    if os.path.islink(path):
        fail("refusing a symlinked workspace directory: %s" % path)
    os.makedirs(path, mode=0o700, exist_ok=True)
    if not os.path.isdir(path) or os.path.islink(path):
        fail("workspace directory %s is not a real directory" % path)


def within(path, root):
    real = os.path.realpath(path)
    base = os.path.realpath(root)
    return real == base or real.startswith(base + os.sep)


def remove_tree(path, root):
    """Remove one workspace-owned path, never following a symlink."""
    if not os.path.lexists(path):
        return
    if os.path.islink(path):
        # Unlink the link itself; never touch its target.
        os.unlink(path)
        return
    if not within(path, root):
        fail("refusing to remove a path outside the workspace: %s" % path)
    if os.path.isdir(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def reset_workspace_dir(path, root):
    remove_tree(path, root)
    os.makedirs(path, mode=0o700, exist_ok=True)
    assert_real_dir(path, "workspace directory")


def tree_size(path):
    total = 0
    for dirpath, dirnames, filenames in os.walk(path, followlinks=False):
        for name in list(dirnames):
            if os.path.islink(os.path.join(dirpath, name)):
                dirnames.remove(name)
        for name in filenames:
            try:
                total += os.lstat(os.path.join(dirpath, name)).st_size
            except OSError:
                pass
    return total


def prune_empty_parents(root, rel):
    """Remove directories that became empty; never touches retained files."""
    current = os.path.dirname(rel)
    while current:
        path = os.path.join(root, current)
        try:
            os.rmdir(path)
        except OSError:
            break
        current = os.path.dirname(current)
'''


PREPARE = PRELUDE + r'''
workspace = CONFIG["workspace"]
workspace = os.path.abspath(workspace)
state = os.path.join(workspace, "state")
attempt = CONFIG["attempt"]
staging = CONFIG["staging"]
attempt_id = CONFIG["attemptId"]

lock_handle = lock(workspace_lock_path(workspace))
try:
    if os.path.lexists(workspace):
        assert_real_dir(workspace, "workspace root")
    lease_path = os.path.join(state, "lease.json")
    lease = read_json(lease_path)
    phase = (lease or {}).get("phase")
    same = bool(lease) and lease.get("attemptId") == attempt_id
    resume = False
    if lease:
        if same and phase in ("updating", "prepared"):
            if os.path.exists(os.path.join(attempt, "dispatch.json")):
                fail("attempt is already dispatched; reconcile it with status")
            if os.path.lexists(attempt) and (os.path.islink(attempt) or not os.path.isdir(attempt)):
                fail("attempt path exists but is not a real directory")
            resume = os.path.lexists(attempt) or os.path.lexists(staging)
        elif phase in ("terminal", "abandoned"):
            pass
        else:
            fail(
                "workspace is busy: phase=%s attempt=%s; reconcile with workspace-status, "
                "cancel that attempt, or reset the workspace"
                % (phase, lease.get("attemptId"))
            )

    # Preflight every path that must not be overwritten. Nothing below this
    # point may replace a prior terminal lease before these checks pass.
    if resume:
        if os.path.lexists(attempt) and (os.path.islink(attempt) or not os.path.isdir(attempt)):
            fail("attempt path is not a real directory")
    else:
        if os.path.lexists(attempt):
            fail("attempt already exists; observe it with status instead of staging again")
        if os.path.lexists(staging):
            fail("attempt staging directory already exists; observe or reset it")

    ensure_dir(workspace)
    for name in ("state", "work", "home", "attempts", "staging"):
        ensure_dir(os.path.join(workspace, name))

    metadata_path = os.path.join(workspace, "workspace.json")
    metadata = read_json(metadata_path)
    binding = {key: CONFIG.get(key) for key in ("key", "label", "repoId", "repoIdentity", "target", "user", "root")}
    if metadata is None:
        binding.update({
            "schemaVersion": 1,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        })
        atomic_json(metadata_path, binding)
    else:
        for key, value in binding.items():
            if metadata.get(key) != value:
                fail(
                    "workspace metadata does not match this binding (%s: %r != %r); "
                    "refusing to reuse it" % (key, metadata.get(key), value)
                )

    previous = lease
    atomic_json(lease_path, {
        "schemaVersion": 2,
        "phase": "updating",
        "attemptId": attempt_id,
        "attemptDir": attempt,
        "unit": CONFIG.get("unit"),
        "inputId": None,
        "clean": bool(CONFIG.get("clean")),
        "startedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "workspace": {key: CONFIG.get(key) for key in ("key", "label", "repoId", "repoIdentity", "target", "user", "root")},
    })
    created_attempt = False
    created_staging = False
    try:
        if CONFIG.get("clean"):
            reset_workspace_dir(os.path.join(workspace, "work"), workspace)
            reset_workspace_dir(os.path.join(workspace, "home"), workspace)
            for name in ("managed.json", "synced.json", "update-incomplete.json"):
                path = os.path.join(state, name)
                if os.path.lexists(path):
                    remove_tree(path, workspace)
        if resume:
            reset_workspace_dir(staging, workspace)
            created_staging = True
        else:
            os.mkdir(attempt)
            created_attempt = True
            os.mkdir(staging, 0o700)
            created_staging = True
        os.mkdir(os.path.join(staging, "work"), 0o700)
        if not os.path.exists(os.path.join(state, "managed.json")):
            if os.listdir(os.path.join(workspace, "work")):
                fail(
                    "workspace has content but no managed manifest; it was not created by "
                    "remote-exec. Reset the workspace before reuse."
                )
        atomic_json(os.path.join(attempt, "state.json"), {
            "schemaVersion": 2, "phase": "preparing", "attemptId": attempt_id,
        })
    except BaseException:
        # A failed preparation must not leave a lease claiming this attempt.
        try:
            if created_staging and os.path.lexists(staging):
                remove_tree(staging, workspace)
            if created_attempt and os.path.lexists(attempt):
                remove_tree(attempt, workspace)
            if previous is None:
                if os.path.lexists(lease_path):
                    os.unlink(lease_path)
            else:
                atomic_json(lease_path, previous)
        finally:
            pass
        raise
finally:
    unlock(lock_handle)
print(json.dumps({"workspace": workspace, "phase": "updating", "resumed": resume}))

'''


SYNC = PRELUDE + r'''
workspace = CONFIG["workspace"]
work = os.path.join(workspace, "work")
state = os.path.join(workspace, "state")
attempt = CONFIG["attempt"]
attempt_id = CONFIG["attemptId"]
manifest = load_module("remote_exec_manifest", CONFIG["manifestModule"])
lease_path = os.path.join(state, "lease.json")
managed_path = os.path.join(state, "managed.json")
incomplete_path = os.path.join(state, "update-incomplete.json")
lock_handle = lock(workspace_lock_path(workspace))
try:
    assert_real_dir(workspace, "workspace root")
    assert_real_dir(work, "workspace work directory")
    assert_real_dir(os.path.dirname(CONFIG["stagingWork"]), "attempt staging directory")
    assert_real_dir(CONFIG["stagingWork"], "attempt staging work directory")
    lease = read_json(lease_path) or {}
    if lease.get("attemptId") != attempt_id or lease.get("phase") not in ("updating", "prepared"):
        fail("workspace lease is not owned by this attempt; refusing to sync (phase=%s)" % lease.get("phase"))

    value = manifest.load_manifest(CONFIG["inputManifest"])
    if value.get("inputId") != CONFIG["inputId"]:
        fail("staged input manifest does not match the captured input id")

    new_entries = {entry["path"]: entry for entry in value["files"]}
    payload_plan = None
    payload_paths = None
    if CONFIG.get("payloadFile"):
        payload_plan = read_json(CONFIG["payloadFile"])
        if not payload_plan or payload_plan.get("inputId") != CONFIG["inputId"]:
            fail("upload plan does not match the captured input")
        payload_paths = set(payload_plan.get("payload") or [])
        for rel in sorted(payload_paths):
            if rel not in new_entries or new_entries[rel].get("type") != "file":
                fail("upload plan names %r, which is not a captured file" % rel)
            staged = os.path.join(CONFIG["stagingWork"], rel)
            try:
                observed = manifest.describe(CONFIG["stagingWork"], rel)
            except (FileNotFoundError, NotADirectoryError):
                fail("payload file %r is missing from the staged upload" % rel)
            if observed != new_entries[rel]:
                fail("payload file %r does not match the captured digest or mode" % rel)
        if os.path.isdir(CONFIG["stagingWork"]):
            extras = set(manifest.tree_entries(CONFIG["stagingWork"])) - payload_paths
            if extras:
                fail("staged upload contains unplanned payload: %s" % sorted(extras)[:5])
    else:
        # Backward-compatible full staging directory: the whole tree must match.
        manifest.verify(CONFIG["stagingWork"], CONFIG["inputManifest"], CONFIG["inputId"])

    incomplete = read_json(incomplete_path)
    resume = False
    if incomplete:
        if incomplete.get("attemptId") != attempt_id:
            fail(
                "workspace has an incomplete update from attempt %s; retry that attempt or "
                "reset the workspace" % incomplete.get("attemptId")
            )
        if incomplete.get("inputId") != CONFIG["inputId"]:
            fail("incomplete update belongs to a different input; reset the workspace")
        resume = True

    managed = read_json(managed_path)
    old_entries = {}
    if managed is None:
        if os.listdir(work):
            fail("workspace has content but no managed manifest; reset it before reuse")
    else:
        for entry in managed.get("entries") or []:
            old_entries[entry["path"]] = entry
        for rel in managed.get("missing") or []:
            old_entries[rel] = None

    atomic_json(incomplete_path, {
        "schemaVersion": 1,
        "attemptId": attempt_id,
        "inputId": CONFIG["inputId"],
        "startedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "resume": resume,
    })

    def current_state(rel):
        path = os.path.join(work, rel)
        try:
            info = os.lstat(path)
        except (FileNotFoundError, NotADirectoryError):
            return None
        if stat.S_ISDIR(info.st_mode):
            return "DIR"
        if stat.S_ISLNK(info.st_mode) or stat.S_ISREG(info.st_mode):
            return manifest.describe(work, rel)
        return "OTHER"

    def assert_safe_ancestors(rel):
        parts = rel.split("/")
        current = work
        for index in range(1, len(parts)):
            current = os.path.join(current, parts[index - 1])
            try:
                info = os.lstat(current)
            except (FileNotFoundError, NotADirectoryError):
                return
            if stat.S_ISLNK(info.st_mode):
                fail("hostile symlinked ancestor %r for managed path %r" % (current, rel))
            if not stat.S_ISDIR(info.st_mode):
                parent = os.path.relpath(current, work).replace(os.sep, "/")
                if parent in new_entries:
                    fail("manifest names %r as both a file and a directory parent" % parent)
                expected = old_entries.get(parent, "unmanaged")
                if expected == "unmanaged" or expected is None:
                    fail("non-directory ancestor %r for managed path %r" % (current, rel))
                if not same(current_state(parent), expected):
                    fail("managed ancestor %r changed outside remote-exec; reset instead" % parent)
                # A formerly managed file that is replaced by a directory is
                # removed as an ancestor below; it is not a collision.

    def same(current, expected):
        return current == expected

    # 1. Every previously managed path must still be in the state the last
    #    attempt left it in; an edit made outside remote-exec fails closed.
    for rel, expected in old_entries.items():
        assert_safe_ancestors(rel)
        current = current_state(rel)
        if expected is None:
            if current is not None and not (resume and rel in new_entries and same(current, new_entries[rel])):
                fail("managed path %r changed outside remote-exec; collect or reset instead of overwriting" % rel)
        elif not same(current, expected):
            partial = resume and (
                (rel in new_entries and same(current, new_entries[rel]))
                or (rel not in new_entries and current is None)
            )
            if not partial:
                fail("managed source %r changed outside remote-exec; collect or reset instead of overwriting" % rel)

    # 2. A new source path must not collide with retained build output.
    directory_targets = set()
    for rel, entry in new_entries.items():
        assert_safe_ancestors(rel)
        current = current_state(rel)
        if rel not in old_entries and current is not None:
            if resume and (
                same(current, entry)
                or (
                    isinstance(current, dict)
                    and current.get("type") == entry.get("type")
                    and current.get("sha256") == entry.get("sha256")
                    and current.get("size") == entry.get("size")
                    and current.get("target") == entry.get("target")
                )
            ):
                # This exact path was already installed by the interrupted sync.
                continue
            if current == "DIR":
                discardable = True
                root_path = os.path.join(work, rel)
                for dirpath, dirnames, filenames in os.walk(root_path, followlinks=False):
                    for name in list(dirnames):
                        full = os.path.join(dirpath, name)
                        if os.path.islink(full):
                            discardable = False
                            dirnames.remove(name)
                    for name in filenames:
                        full = os.path.join(dirpath, name)
                        child = os.path.relpath(full, work).replace(os.sep, "/")
                        if child in new_entries:
                            discardable = False
                            continue
                        if old_entries.get(child) is None:
                            discardable = False
                            continue
                        if not same(current_state(child), old_entries[child]):
                            discardable = False
                if not discardable:
                    fail("new source %r collides with retained directory content" % rel)
                directory_targets.add(rel)
            else:
                fail("new source %r collides with existing retained content; reset or remove it" % rel)

    # 3. A managed file can become a directory ancestor of new source.
    ancestor_removals = set()
    for rel in new_entries:
        parts = rel.split("/")
        for index in range(1, len(parts)):
            parent = "/".join(parts[:index])
            current = current_state(parent)
            if current is None or current == "DIR":
                continue
            if parent in new_entries:
                fail("manifest names %r as both a file and a directory parent" % parent)
            expected = old_entries.get(parent)
            if expected is not None and same(current, expected):
                ancestor_removals.add(parent)
            else:
                fail("unmanaged %r blocks a directory needed by %r; refusing to remove retained content" % (parent, rel))

    deletions = sorted(
        (rel for rel in old_entries if rel not in new_entries),
        key=lambda rel: rel.count("/"),
        reverse=True,
    )
    removals = sorted(set(deletions) | ancestor_removals, key=lambda rel: rel.count("/"), reverse=True)

    changed = {"added": 0, "modified": 0, "deleted": 0, "unchanged": 0}
    for rel in removals:
        assert_safe_ancestors(rel)
        path = os.path.join(work, rel)
        current = current_state(rel)
        if current is None:
            continue
        if current == "DIR":
            fail("managed path %r became a directory outside remote-exec; reset instead" % rel)
        os.unlink(path)
        changed["deleted"] += 1
        if os.path.dirname(rel):
            prune_empty_parents(work, rel)

    for rel in sorted(directory_targets, key=lambda value: value.count("/"), reverse=True):
        path = os.path.join(work, rel)
        if not os.path.lexists(path):
            continue
        if os.path.islink(path) or not os.path.isdir(path):
            continue
        for dirpath, dirnames, filenames in os.walk(path, topdown=False, followlinks=False):
            if filenames:
                fail("retained files remain inside new source directory path %r" % rel)
            for name in dirnames:
                candidate = os.path.join(dirpath, name)
                if os.path.islink(candidate):
                    fail("retained symlink blocks new source directory path %r" % rel)
                if os.path.lexists(candidate):
                    os.rmdir(candidate)
            if os.path.lexists(dirpath):
                os.rmdir(dirpath)

    def ensure_parents(rel):
        parts = rel.split("/")
        current = work
        for index in range(1, len(parts)):
            current = os.path.join(current, parts[index - 1])
            try:
                info = os.lstat(current)
            except FileNotFoundError:
                os.mkdir(current, 0o755)
                continue
            if stat.S_ISLNK(info.st_mode):
                fail("hostile symlinked ancestor %r for %r" % (current, rel))
            if not stat.S_ISDIR(info.st_mode):
                fail("non-directory ancestor %r for %r" % (current, rel))

    def install(rel, entry):
        source = os.path.join(CONFIG["stagingWork"], rel)
        destination = os.path.join(work, rel)
        directory = os.path.dirname(destination) or work
        if not within(directory, work):
            fail("path %r escapes the workspace" % rel)
        temporary = os.path.join(
            directory, ".remote-exec-tmp-%d-%s" % (os.getpid(), os.urandom(6).hex())
        )
        try:
            if entry["type"] == "symlink":
                os.symlink(entry["target"], temporary)
                os.replace(temporary, destination)
            else:
                fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "wb") as writer, open(source, "rb") as reader:
                    shutil.copyfileobj(reader, writer, 1 << 20)
                    writer.flush()
                    os.fsync(writer.fileno())
                os.chmod(temporary, 0o755 if entry["mode"] == manifest.EXEC_MODE else 0o644)
                # A changed file gets a current mtime so mtime-based build tools
                # notice it; unchanged files are never touched and keep theirs.
                now = time.time()
                os.utime(temporary, ns=(int(now * 1e9), int(now * 1e9)))
                os.replace(temporary, destination)
        except BaseException:
            try:
                os.unlink(temporary)
            except OSError:
                pass
            raise

    for rel in sorted(new_entries):
        entry = new_entries[rel]
        assert_safe_ancestors(rel)
        ensure_parents(rel)
        current = current_state(rel)
        if same(current, entry):
            changed["unchanged"] += 1
            continue
        if current == "DIR":
            fail("retained directory still occupies new source %r" % rel)
        if payload_paths is not None and rel not in payload_paths:
            if entry["type"] == "symlink":
                if current is not None:
                    os.unlink(os.path.join(work, rel))
                install(rel, entry)
                changed["added" if current is None else "modified"] += 1
                continue
            if (
                isinstance(current, dict)
                and current.get("type") == "file"
                and current.get("sha256") == entry.get("sha256")
                and current.get("size") == entry.get("size")
            ):
                # Same bytes, different executable bit: no payload needed.
                os.chmod(
                    os.path.join(work, rel),
                    0o755 if entry["mode"] == manifest.EXEC_MODE else 0o644,
                )
                changed.setdefault("modeOnly", 0)
                changed["modeOnly"] += 1
                continue
            fail(
                "payload for changed source %r was not uploaded; refusing a partial "
                "reconciliation" % rel
            )
        install(rel, entry)
        changed["added" if current is None else "modified"] += 1

    observed = manifest.entries_for(work, new_entries.keys())
    expected = [new_entries[rel] for rel in sorted(new_entries)]
    if observed != expected:
        fail("workspace reconciliation did not produce the captured input; reset the workspace")

    entries = [new_entries[rel] for rel in sorted(new_entries)]
    atomic_json(managed_path, {
        "schemaVersion": 1,
        "inputId": CONFIG["inputId"],
        "attemptId": attempt_id,
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "entries": entries,
        "missing": [],
    })
    atomic_json(os.path.join(state, "synced.json"), {
        "schemaVersion": 2,
        "workspaceVersion": CONFIG["version"],
        "attemptId": attempt_id,
        "inputId": CONFIG["inputId"],
        "baseRevision": value.get("baseRevision"),
        "files": len(entries),
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })
    lease.update({
        "phase": "prepared",
        "inputId": CONFIG["inputId"],
        "workspaceVersion": CONFIG["version"],
    })
    atomic_json(lease_path, lease)
    try:
        os.unlink(incomplete_path)
    except FileNotFoundError:
        pass
finally:
    unlock(lock_handle)
print(json.dumps({"workspaceVersion": CONFIG["version"], "inputId": CONFIG["inputId"], "changed": changed}))
'''


PLAN = PRELUDE + r'''
workspace = CONFIG["workspace"]
state = os.path.join(workspace, "state")
manifest = load_module("remote_exec_manifest", CONFIG["manifestModule"])
lease_path = os.path.join(state, "lease.json")
lock_handle = lock(workspace_lock_path(workspace))
try:
    lease = read_json(lease_path) or {}
    if lease.get("attemptId") != CONFIG["attemptId"] or lease.get("phase") not in ("updating", "prepared"):
        fail("workspace lease is not owned by this attempt; refusing to plan (phase=%s)" % lease.get("phase"))
    value = manifest.load_manifest(CONFIG["inputManifest"])
    if value.get("inputId") != CONFIG["inputId"]:
        fail("staged input manifest does not match the captured input id")
    entries = {entry["path"]: entry for entry in value["files"]}
    managed = read_json(os.path.join(state, "managed.json"))
    old_entries = {}
    if managed is not None:
        for entry in managed.get("entries") or []:
            old_entries[entry["path"]] = entry
        for rel in managed.get("missing") or []:
            old_entries[rel] = None

    payload = []
    mode_only = []
    symlink_changes = []
    unchanged = 0
    for rel in sorted(entries):
        new = entries[rel]
        old = old_entries.get(rel)
        if old is not None and old == new:
            unchanged += 1
            continue
        if new["type"] == "symlink":
            symlink_changes.append(rel)
            continue
        if (
            old is not None
            and old.get("type") == "file"
            and old.get("sha256") == new.get("sha256")
            and old.get("size") == new.get("size")
        ):
            mode_only.append(rel)
            continue
        payload.append(rel)
    deleted = sorted(rel for rel in old_entries if rel not in entries)
    payload_bytes = sum(entries[rel]["size"] for rel in payload)
    atomic_json(CONFIG["payloadFile"], {
        "schemaVersion": 1,
        "attemptId": CONFIG["attemptId"],
        "inputId": CONFIG["inputId"],
        "payload": payload,
        "modeOnly": mode_only,
        "symlinkChanges": symlink_changes,
        "unchanged": unchanged,
        "deleted": deleted,
        "files": len(entries),
        "payloadBytes": payload_bytes,
    })
finally:
    unlock(lock_handle)
print(json.dumps({
    "payload": payload,
    "payloadFiles": len(payload),
    "payloadBytes": payload_bytes,
    "modeOnly": len(mode_only),
    "symlinkChanges": len(symlink_changes),
    "unchanged": unchanged,
    "deleted": len(deleted),
    "files": len(entries),
}))
'''


FINALIZE = PRELUDE + r'''
attempt = CONFIG["attemptDir"]
work = CONFIG["workDir"]
manifest = load_module("remote_exec_manifest", CONFIG["manifestModule"])
boundary = load_module("remote_exec_boundary", CONFIG["boundaryModule"])

assert_real_dir(work, "workspace work directory")
selection = load_module("remote_exec_selection", CONFIG["selectionModule"])
baseline = manifest.load_manifest(CONFIG["inputManifest"])
base_paths = [entry["path"] for entry in baseline["files"]]

def work_state(rel):
    path = os.path.join(work, rel)
    try:
        info = os.lstat(path)
    except (FileNotFoundError, NotADirectoryError):
        return None
    if stat.S_ISDIR(info.st_mode):
        return "OTHER"
    if stat.S_ISLNK(info.st_mode) or stat.S_ISREG(info.st_mode):
        assert_safe(rel)
        if os.path.islink(path):
            return manifest.describe(work, rel)
        if not within(path, work):
            fail("managed path %r resolves outside the workspace" % rel)
        return manifest.describe(work, rel)
    return "OTHER"


def assert_safe(rel):
    parts = rel.split("/")
    current = work
    for index in range(1, len(parts)):
        current = os.path.join(current, parts[index - 1])
        try:
            info = os.lstat(current)
        except (FileNotFoundError, NotADirectoryError):
            return
        if stat.S_ISLNK(info.st_mode):
            fail("hostile symlinked ancestor %r for selected path %r" % (current, rel))
        if not stat.S_ISDIR(info.st_mode):
            fail("non-directory ancestor %r for selected path %r" % (current, rel))


def git_selected():
    try:
        return selection.git_selected(
            work,
            os.path.join(attempt, "selection.git"),
            os.path.join(attempt, "finalize-home"),
        )
    except selection.SelectionError as error:
        fail(str(error))

# Managed-source receipt: the state the next sync may expect to find. Written
# even when snapshotting later fails, so a later run reconciles against truth.
managed_entries = []
managed_missing = []
for rel in base_paths:
    value = work_state(rel)
    if isinstance(value, dict):
        managed_entries.append(value)
    else:
        managed_missing.append(rel)
managed_lock = lock(workspace_lock_path(CONFIG["workspace"]))
try:
    manifest.write_manifest({
        "schemaVersion": 1,
        "inputId": baseline["inputId"],
        "entries": managed_entries,
        "missing": sorted(managed_missing),
    }, CONFIG["managedFile"])
finally:
    unlock(managed_lock)

selected = [rel for rel in base_paths if os.path.lexists(os.path.join(work, rel))]
for rel in sorted(set(git_selected()) - set(base_paths)):
    manifest.validate_relpath(rel)
    reason = boundary.forbidden_reason(rel)
    if reason:
        fail("%r is a %s; refusing to snapshot it" % (rel, reason))
    selected.append(rel)
selected = sorted(set(selected))

snapshot = CONFIG["snapshotDir"]
if os.path.lexists(snapshot):
    if os.path.islink(snapshot) or not os.path.isdir(snapshot):
        fail("snapshot target is not a directory")
    if os.listdir(snapshot):
        fail("snapshot target is not empty")
else:
    os.makedirs(snapshot, 0o700)

for rel in selected:
    assert_safe(rel)
    source = os.path.join(work, rel)
    destination = os.path.join(snapshot, rel)
    info = os.lstat(source)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    if stat.S_ISLNK(info.st_mode):
        target = manifest.validate_symlink(rel, os.readlink(source))
        os.symlink(target, destination)
    elif stat.S_ISREG(info.st_mode):
        if not within(source, work):
            fail("source %r resolves outside the workspace" % rel)
        shutil.copyfile(source, destination)
        os.chmod(destination, 0o755 if info.st_mode & 0o111 else 0o644)
        os.utime(destination, ns=(info.st_atime_ns, info.st_mtime_ns))
    else:
        fail("unsupported output type at %r" % rel)

output = manifest.build_selection(snapshot, selected, baseline.get("baseRevision"))
manifest.write_manifest(output, CONFIG["outputManifest"])
print(json.dumps({
    "status": "ok",
    "inputId": output["inputId"],
    "files": len(selected),
    "managedPresent": len(managed_entries),
    "managedMissing": len(managed_missing),
}))
'''


SNOOP = PRELUDE + r'''
workspace = CONFIG["workspace"]
if not os.path.isdir(workspace) or os.path.islink(workspace):
    print(json.dumps({"exists": False}))
    raise SystemExit(0)
state = os.path.join(workspace, "state")
def load(name):
    return read_json(os.path.join(state, name))
lease = load("lease.json")
managed = load("managed.json")
synced = load("synced.json")
incomplete = load("update-incomplete.json")
attempts = []
attempts_dir = os.path.join(workspace, "attempts")
if os.path.isdir(attempts_dir) and not os.path.islink(attempts_dir):
    for name in sorted(os.listdir(attempts_dir)):
        path = os.path.join(attempts_dir, name)
        if os.path.islink(path) or not os.path.isdir(path):
            continue
        result = read_json(os.path.join(path, "result.json"))
        attempts.append({
            "attemptId": name,
            "terminal": bool(result),
            "phase": (result or {}).get("phase"),
            "finishedAt": (result or {}).get("finishedAt"),
            "hasInput": os.path.exists(os.path.join(path, "input.json")),
            "hasDispatch": os.path.exists(os.path.join(path, "dispatch.json")),
            "hasResult": bool(result),
        })
usage = 0
for dirpath, dirnames, filenames in os.walk(workspace, followlinks=False):
    for name in list(dirnames):
        if os.path.islink(os.path.join(dirpath, name)):
            dirnames.remove(name)
    for name in filenames:
        path = os.path.join(dirpath, name)
        try:
            usage += os.lstat(path).st_size
        except OSError:
            pass
print(json.dumps({
    "exists": True,
    "workspace": workspace,
    "metadata": read_json(os.path.join(workspace, "workspace.json")),
    "lease": lease,
    "synced": synced,
    "managed": None if managed is None else {
        "inputId": managed.get("inputId"),
        "attemptId": managed.get("attemptId"),
        "present": len(managed.get("entries") or []),
        "missing": managed.get("missing") or [],
    },
    "updateIncomplete": incomplete,
    "attempts": attempts[-20:],
    "bytes": usage,
}))
'''


COMPLETE_LEASE = PRELUDE + r'''
workspace = CONFIG["workspace"]
state = os.path.join(workspace, "state")
lease_path = os.path.join(state, "lease.json")
lock_handle = lock(workspace_lock_path(workspace))
try:
    lease = read_json(lease_path)
    if not lease or lease.get("attemptId") != CONFIG["attemptId"]:
        print(json.dumps({"changed": False, "reason": "lease is not owned by this attempt"}))
        raise SystemExit(0)
    phase = lease.get("phase")
    if phase in ("terminal", "abandoned"):
        print(json.dumps({"changed": False, "reason": "lease already %s" % phase}))
        raise SystemExit(0)

    attempt_dir = lease.get("attemptDir")
    result = read_json(os.path.join(attempt_dir, "result.json")) if attempt_dir else None
    result_phase = (result or {}).get("phase")
    unit = lease.get("unit")
    unit_active = False
    if unit:
        env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/%d" % os.getuid())
        probe = subprocess.run(
            ["systemctl", "--user", "show", "-p", "ActiveState", unit],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
        )
        unit_active = (
            b"ActiveState=active" in probe.stdout
            or b"ActiveState=activating" in probe.stdout
            or b"ActiveState=reloading" in probe.stdout
        )

    if result is not None:
        if result_phase in ("succeeded", "failed", "cancelled"):
            if unit_active:
                print(json.dumps({
                    "changed": False,
                    "reason": "unit %s is still active; not releasing the lease" % unit,
                }))
                raise SystemExit(0)
            lease.update({
                "phase": "terminal",
                "resultPhase": result_phase,
                "finishedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            })
        elif result_phase == "unknown":
            lease.update({
                "phase": "unknown",
                "resultPhase": "unknown",
                "reason": (result or {}).get("reason") or "terminal result is unknown",
                "finishedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            })
        else:
            print(json.dumps({"changed": False, "reason": "result has no releasable phase"}))
            raise SystemExit(0)
    elif CONFIG.get("abandon") and phase in ("updating", "prepared"):
        if os.path.exists(os.path.join(state, "update-incomplete.json")):
            print(json.dumps({
                "changed": False,
                "reason": "a partial sync exists; reset the workspace instead of abandoning",
            }))
            raise SystemExit(0)
        lease.update({
            "phase": "abandoned",
            "reason": CONFIG.get("reason") or "preparation was never dispatched",
            "finishedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        })
    else:
        print(json.dumps({"changed": False, "reason": "no terminal result"}))
        raise SystemExit(0)
    atomic_json(lease_path, lease)
finally:
    unlock(lock_handle)
print(json.dumps({"changed": True, "lease": lease}))

'''


RESET = PRELUDE + r'''
workspace = CONFIG["workspace"]
if not os.path.isdir(workspace) or os.path.islink(workspace):
    print(json.dumps({"reset": False, "reason": "workspace does not exist"}))
    raise SystemExit(0)
state = os.path.join(workspace, "state")
lock_handle = lock(workspace_lock_path(workspace))
try:
    lease = read_json(os.path.join(state, "lease.json")) or {}
    phase = lease.get("phase")
    attempt_dir = lease.get("attemptDir")
    dispatched = bool(attempt_dir) and os.path.exists(os.path.join(attempt_dir, "dispatch.json"))
    result_exists = bool(attempt_dir) and os.path.exists(os.path.join(attempt_dir, "result.json"))
    result = read_json(os.path.join(attempt_dir, "result.json")) if result_exists else None
    result_phase = (result or {}).get("phase")
    known_terminal = result_phase in ("succeeded", "failed", "cancelled")
    unknown_outcome = result_exists and not known_terminal

    unit_active = False
    if lease.get("unit"):
        env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/%d" % os.getuid())
        probe = subprocess.run(
            ["systemctl", "--user", "show", "-p", "ActiveState", lease["unit"]],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
        )
        unit_active = (
            b"ActiveState=active" in probe.stdout
            or b"ActiveState=activating" in probe.stdout
            or b"ActiveState=reloading" in probe.stdout
        )
    child_alive = False
    pid = lease.get("childPid")
    if pid:
        try:
            os.kill(pid, 0)
            child_alive = True
        except ProcessLookupError:
            pass
        except PermissionError:
            child_alive = True
    if unit_active or child_alive:
        fail(
            "workspace still has a live unit or process (unit=%s child=%s); cancel it before reset"
            % (lease.get("unit"), pid)
        )

    if phase in ("updating", "prepared"):
        if dispatched and not known_terminal and not CONFIG.get("force"):
            fail(
                "a dispatched attempt has no known terminal result; reconcile with workspace-status, "
                "cancel it, and use --force only after verifying no process can be running"
            )
    elif phase == "running":
        if not known_terminal and not CONFIG.get("force"):
            fail(
                "workspace outcome is unknown; reconcile with workspace-status and use --force only "
                "after verifying no process can be running"
            )
    elif phase == "unknown":
        if not CONFIG.get("force"):
            fail("workspace outcome is unknown; use --force only after verifying no process can be running")
    elif phase in ("terminal", "abandoned", None):
        if unknown_outcome and not CONFIG.get("force"):
            fail("workspace has an unknown or invalid result; use --force only after verifying no process can be running")
    else:
        fail("workspace lease is in an unrecognised phase %r; refusing to reset" % phase)
    for name in ("work", "home") if CONFIG.get("cleanHome") else ("work",):
        path = os.path.join(workspace, name)
        remove_tree(path, workspace)
        ensure_dir(path)
    for name in ("managed.json", "synced.json", "update-incomplete.json"):
        path = os.path.join(state, name)
        if os.path.lexists(path):
            remove_tree(path, workspace)
    staging_dir = os.path.join(workspace, "staging")
    if os.path.lexists(staging_dir):
        if os.path.islink(staging_dir):
            os.unlink(staging_dir)
            os.mkdir(staging_dir, 0o700)
        else:
            for name in sorted(os.listdir(staging_dir)):
                remove_tree(os.path.join(staging_dir, name), workspace)
    lease.update({
        "phase": "abandoned",
        "reason": "workspace reset",
        "attemptId": None,
        "inputId": None,
        "finishedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })
    atomic_json(os.path.join(state, "lease.json"), lease)
finally:
    unlock(lock_handle)
print(json.dumps({"reset": True, "cleanHome": bool(CONFIG.get("cleanHome"))}))
'''


PRUNE = PRELUDE + r'''
workspace = CONFIG["workspace"]
if not os.path.isdir(workspace) or os.path.islink(workspace):
    print(json.dumps({"workspace": workspace, "skipped": "does not exist", "removed": [], "kept": []}))
    raise SystemExit(0)
state = os.path.join(workspace, "state")
lock_handle = lock(workspace_lock_path(workspace))
removed = []
kept = []
try:
    lease = read_json(os.path.join(state, "lease.json")) or {}
    phase = lease.get("phase")
    if phase not in ("terminal", "abandoned", None):
        print(json.dumps({
            "workspace": workspace,
            "skipped": "lease phase %s is not terminal" % phase,
            "removed": [],
            "kept": [],
        }))
        raise SystemExit(0)
    attempts_dir = os.path.join(workspace, "attempts")
    candidates = []
    if os.path.isdir(attempts_dir) and not os.path.islink(attempts_dir):
        for name in sorted(os.listdir(attempts_dir)):
            path = os.path.join(attempts_dir, name)
            if os.path.islink(path) or not os.path.isdir(path):
                continue
            result = read_json(os.path.join(path, "result.json"))
            if not result:
                kept.append({"attemptId": name, "reason": "not terminal"})
                continue
            finished = result.get("finishedAt") or ""
            try:
                import calendar
                epoch = calendar.timegm(time.strptime(finished, "%Y-%m-%dT%H:%M:%SZ"))
            except (ValueError, TypeError):
                epoch = int(os.lstat(path).st_mtime)
            candidates.append((epoch, name, path))
    candidates.sort(reverse=True)
    retained_terminal = []
    for index, (epoch, name, path) in enumerate(candidates):
        reason = None
        if index < CONFIG["keep"]:
            reason = "within keep count"
        elif epoch > CONFIG["cutoff"]:
            reason = "younger than retention"
        if reason:
            kept.append({"attemptId": name, "reason": reason})
            retained_terminal.append((epoch, name, path))
            continue
        if not CONFIG.get("apply"):
            removed.append({"attemptId": name, "dryRun": True})
            continue
        if not within(path, attempts_dir):
            fail("attempt path escapes the workspace: %s" % path)
        shutil.rmtree(path)
        removed.append({"attemptId": name})
    # The lease is terminal, so every remaining staging directory belongs to a
    # preparation that will never dispatch. It is an input copy, not a receipt.
    staging_dir = os.path.join(workspace, "staging")
    if os.path.islink(staging_dir):
        kept.append({"staging": "staging", "reason": "staging directory is a symlink; reset required"})
    elif os.path.isdir(staging_dir):
        for name in sorted(os.listdir(staging_dir)):
            path = os.path.join(staging_dir, name)
            if os.path.islink(path):
                kept.append({"staging": name, "reason": "symlinked staging path; reset required"})
                continue
            if not os.path.isdir(path):
                continue
            if CONFIG.get("apply"):
                if not within(path, staging_dir):
                    fail("staging path escapes the workspace: %s" % path)
                shutil.rmtree(path)
            else:
                removed.append({"staging": name, "dryRun": True})
    budget = CONFIG.get("maxBytes")
    usage = tree_size(workspace)
    if budget is not None:
        for epoch, name, path in sorted(retained_terminal):
            if usage <= budget:
                break
            size = tree_size(path)
            if CONFIG.get("apply"):
                if not within(path, attempts_dir):
                    fail("attempt path escapes the workspace: %s" % path)
                shutil.rmtree(path)
                removed.append({"attemptId": name, "budget": True})
            else:
                removed.append({"attemptId": name, "budget": True, "dryRun": True})
            usage -= size
finally:
    unlock(lock_handle)
print(json.dumps({
    "workspace": workspace,
    "removed": removed,
    "kept": kept,
    "bytes": tree_size(workspace),
    "maxBytes": CONFIG.get("maxBytes"),
    "apply": bool(CONFIG.get("apply")),
}))
'''


LIST_WORKSPACES = PRELUDE + r'''
root = CONFIG["root"]
base = os.path.join(root, "workspaces")
entries = []
if os.path.isdir(base) and not os.path.islink(base):
    for name in sorted(os.listdir(base)):
        path = os.path.join(base, name)
        if os.path.islink(path) or not os.path.isdir(path):
            continue
        metadata = read_json(os.path.join(path, "workspace.json"))
        if not metadata:
            continue
        lease = read_json(os.path.join(path, "state", "lease.json")) or {}
        synced = read_json(os.path.join(path, "state", "synced.json")) or {}
        entries.append({
            "key": name,
            "path": path,
            "metadata": metadata,
            "leasePhase": lease.get("phase"),
            "lastSync": synced.get("at"),
        })
print(json.dumps({"workspaces": entries}))
'''


REMOVE_WORKSPACE = PRELUDE + r'''
base = os.path.join(CONFIG["root"], "workspaces")
workspace = CONFIG["workspace"]
if os.path.dirname(os.path.realpath(workspace)) != os.path.realpath(base):
    fail("workspace is not directly under the workspace root")
if os.path.islink(workspace) or not os.path.isdir(workspace):
    print(json.dumps({"removed": False, "reason": "not a real workspace directory"}))
    raise SystemExit(0)
state = os.path.join(workspace, "state")
lock_handle = lock(workspace_lock_path(workspace))
try:
    lease = read_json(os.path.join(state, "lease.json")) or {}
    if lease.get("phase") not in ("terminal", "abandoned", None):
        print(json.dumps({"removed": False, "reason": "lease phase %s" % lease.get("phase")}))
        raise SystemExit(0)
    if CONFIG.get("cutoff") is not None:
        import calendar

        synced = read_json(os.path.join(state, "synced.json")) or {}
        stamp = synced.get("at") or lease.get("finishedAt") or ""
        try:
            epoch = calendar.timegm(time.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ"))
        except (ValueError, TypeError):
            epoch = int(os.lstat(workspace).st_mtime)
        if epoch > CONFIG["cutoff"]:
            print(json.dumps({"removed": False, "reason": "workspace is younger than retention"}))
            raise SystemExit(0)
    if not CONFIG.get("apply"):
        print(json.dumps({"removed": False, "dryRun": True}))
        raise SystemExit(0)
    marker = os.path.join(state, "pruning")
    atomic_json(marker, {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    # Hold the external lock across deletion: a new PREPARE for this key waits
    # instead of creating a generation that would be removed underneath it.
    shutil.rmtree(workspace)
finally:
    unlock(lock_handle)
print(json.dumps({"removed": True}))
'''
