"""Self-contained scripts executed on the executor.

`RUNNER` is installed into the attempt directory and started by the executor's
user systemd manager. systemd owns the unit's cgroup, so the attempt survives
an SSH disconnect and a stop kills the whole tree, not just the SSH session.
The runner writes `state.json` while it lives and one atomic `result.json`.

`STATUS` reports the durable terminal state and the unit state; it never starts
or restarts anything. `SELECT` computes the selected output (baseline input
plus new project-nonignored source) with a sanitized Git metadata directory
outside `work/`, then writes an output manifest.
"""

RUNNER = r'''
import base64, fcntl, json, os, platform, signal, subprocess, sys, time

CONFIG = json.loads(open(sys.argv[1], "r", encoding="utf-8").read())


def atomic_json(path, value):
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def boot_id():
    try:
        with open("/proc/sys/kernel/random/boot_id", "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def start_time(pid):
    try:
        with open("/proc/%d/stat" % pid, "r", encoding="utf-8") as handle:
            return handle.read().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def digest(path):
    import hashlib
    value = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        while True:
            block = handle.read(1 << 20)
            if not block:
                break
            value.update(block)
            size += len(block)
    return {"sha256": value.hexdigest(), "size": size}


def main():
    attempt = os.path.realpath(CONFIG["attemptDir"])
    work = os.path.realpath(CONFIG["workDir"])
    workspace = CONFIG.get("workspaceDir")
    if workspace:
        workspace = os.path.realpath(workspace)
        if work != os.path.join(workspace, "work"):
            raise SystemExit("work directory is not the workspace work directory")
        if attempt != CONFIG["attemptDir"] or not attempt.startswith(os.path.join(workspace, "attempts") + os.sep):
            raise SystemExit("attempt directory escapes the workspace")
    elif work != attempt and not work.startswith(attempt + os.sep):
        raise SystemExit("work directory escapes the attempt directory")
    cwd = os.path.realpath(os.path.join(work, CONFIG.get("cwd") or "."))
    if cwd != work and not cwd.startswith(work + os.sep):
        raise SystemExit("cwd escapes the exported work tree")
    if not os.path.isdir(cwd):
        raise SystemExit("cwd does not exist in the exported work tree")

    result_path = os.path.join(attempt, "result.json")
    if os.path.exists(result_path):
        raise SystemExit("terminal result already exists for this attempt; refusing to run again")
    dispatch = os.path.join(attempt, "dispatch.json")
    try:
        with open(dispatch, "r", encoding="utf-8") as handle:
            claim = json.load(handle)
    except (OSError, ValueError):
        raise SystemExit("no dispatch claim; the attempt was not started by remote-exec")
    if claim.get("attemptId") != CONFIG["attemptId"] or claim.get("inputId") != CONFIG["inputId"]:
        raise SystemExit("dispatch claim does not match this attempt's identity")

    lease_handle = None
    if CONFIG.get("leaseFile"):
        lease_lock = CONFIG.get("leaseLockFile")
        if not lease_lock:
            raise SystemExit("workspace lease lock path is missing")
        lease_handle = open(lease_lock, "a+b")
        fcntl.flock(lease_handle.fileno(), fcntl.LOCK_EX)
        try:
            with open(CONFIG["leaseFile"], "r", encoding="utf-8") as handle:
                lease = json.load(handle)
        except (OSError, ValueError):
            raise SystemExit("workspace lease is missing; refusing to run")
        if lease.get("attemptId") != CONFIG["attemptId"]:
            raise SystemExit("workspace lease is not owned by this attempt; refusing to run")
        if lease.get("phase") not in ("updating", "prepared"):
            raise SystemExit("workspace lease is in phase %r; refusing to run" % lease.get("phase"))
        lease.update({
            "phase": "running",
            "runnerPid": os.getpid(),
            "bootId": boot_id(),
            "unit": CONFIG.get("unit"),
            "childPid": None,
        })
        atomic_json(CONFIG["leaseFile"], lease)
        fcntl.flock(lease_handle.fileno(), fcntl.LOCK_UN)
        lease_handle.close()
        lease_handle = None

    logs = os.path.join(attempt, "logs")
    os.makedirs(logs, exist_ok=True)
    os.makedirs(os.path.join(attempt, "artifacts"), exist_ok=True)
    home = CONFIG.get("homeDir") or os.path.join(attempt, "home")
    os.makedirs(home, exist_ok=True)

    env = dict(CONFIG.get("env") or {})
    env.setdefault("PATH", "/run/current-system/sw/bin")
    env.setdefault("HOME", home)
    env.setdefault("LANG", "C.UTF-8")
    env.setdefault("TMPDIR", os.path.join(attempt, "tmp"))
    env.setdefault("REMOTE_EXEC_ATTEMPT", attempt)
    env.setdefault("REMOTE_EXEC_ARTIFACTS", os.path.join(attempt, "artifacts"))
    if workspace:
        env.setdefault("REMOTE_EXEC_WORKSPACE", workspace)
    os.makedirs(env["TMPDIR"], exist_ok=True)

    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    state = {
        "schemaVersion": 2,
        "phase": "running",
        "attemptId": CONFIG["attemptId"],
        "inputId": CONFIG["inputId"],
        "unit": CONFIG.get("unit"),
        "bootId": boot_id(),
        "runnerPid": os.getpid(),
        "startedAt": started,
    }
    atomic_json(os.path.join(attempt, "state.json"), state)

    stdout_path = os.path.join(logs, "stdout.log")
    stderr_path = os.path.join(logs, "stderr.log")
    stop = {"requested": False}
    child = None

    def request_stop(_signum, _frame):
        stop["requested"] = True
        if child is not None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    phase = "failed"
    reason = None
    code = None
    with open(stdout_path, "wb") as out, open(stderr_path, "wb") as err:
        child = subprocess.Popen(
            CONFIG["argv"],
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=out,
            stderr=err,
            start_new_session=True,
        )
        state["childPid"] = child.pid
        state["childStart"] = start_time(child.pid)
        atomic_json(os.path.join(attempt, "state.json"), state)
        if CONFIG.get("leaseFile"):
            lease_lock = CONFIG.get("leaseLockFile")
            if not lease_lock:
                raise SystemExit("workspace lease lock path is missing")
            lease_handle = open(lease_lock, "a+b")
            fcntl.flock(lease_handle.fileno(), fcntl.LOCK_EX)
            try:
                try:
                    with open(CONFIG["leaseFile"], "r", encoding="utf-8") as lease_file:
                        lease = json.load(lease_file)
                except (OSError, ValueError):
                    lease = None
                if lease and lease.get("attemptId") == CONFIG["attemptId"]:
                    lease["childPid"] = child.pid
                    atomic_json(CONFIG["leaseFile"], lease)
            finally:
                fcntl.flock(lease_handle.fileno(), fcntl.LOCK_UN)
                lease_handle.close()
        try:
            code = child.wait(timeout=CONFIG.get("timeoutSecs"))
            if stop["requested"]:
                phase = "cancelled"
                reason = "stop requested; owned process group confirmed terminated"
            else:
                phase = "succeeded" if code == 0 else "failed"
        except subprocess.TimeoutExpired:
            # systemd's RuntimeMaxSec usually fires first; this is the runner's
            # own bound. Termination is only "cancelled" if the whole group goes.
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
            stop["requested"] = True
            code = None

    if stop["requested"]:
        gone = False
        for _ in range(50):
            try:
                os.killpg(child.pid, 0)
            except ProcessLookupError:
                gone = True
                break
            time.sleep(0.1)
        if gone:
            phase = "cancelled"
            reason = "stop requested; owned process group confirmed terminated"
        else:
            phase = "unknown"
            reason = "process group survived cancellation; outcome unknown"
            code = None

    output = None
    if CONFIG.get("finalizeScript"):
        try:
            with open(CONFIG["finalizeConfig"], "r", encoding="utf-8") as handle:
                finalize_args = base64.b64encode(handle.read().encode("utf-8")).decode("ascii")
            process = subprocess.run(
                [sys.executable, CONFIG["finalizeScript"], finalize_args],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=CONFIG.get("finalizeTimeoutSecs", 600),
                check=False,
            )
            if process.returncode != 0:
                output = {
                    "status": "failed",
                    "error": (
                        process.stderr.decode("utf-8", "replace").strip()
                        or "source snapshot failed"
                    )[:4096],
                }
            else:
                output = json.loads(process.stdout.decode("utf-8"))
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            output = {"status": "failed", "error": str(error)}

    finished = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    result = {
        "schemaVersion": 2,
        "attemptId": CONFIG["attemptId"],
        "inputId": CONFIG["inputId"],
        "command": CONFIG["argv"],
        "startedAt": started,
        "finishedAt": finished,
        "exitCode": code,
        "signal": (-code) if (code is not None and code < 0) else None,
        "phase": phase,
        "logs": {
            "stdout": digest(stdout_path),
            "stderr": digest(stderr_path),
        },
        "node": {"hostname": platform.node(), "machine": platform.machine()},
    }
    if reason:
        result["reason"] = reason
    if output is not None:
        result["output"] = output
    atomic_json(result_path, result)
    state["phase"] = phase
    atomic_json(os.path.join(attempt, "state.json"), state)

    if CONFIG.get("leaseFile"):
        lease_lock = CONFIG.get("leaseLockFile")
        if not lease_lock:
            raise SystemExit("workspace lease lock path is missing")
        lease_handle = open(lease_lock, "a+b")
        fcntl.flock(lease_handle.fileno(), fcntl.LOCK_EX)
        try:
            try:
                with open(CONFIG["leaseFile"], "r", encoding="utf-8") as handle:
                    lease = json.load(handle)
            except (OSError, ValueError):
                lease = None
            if lease and lease.get("attemptId") == CONFIG["attemptId"]:
                lease.update({
                    "phase": "terminal" if phase in ("succeeded", "failed", "cancelled") else "unknown",
                    "resultPhase": phase,
                    "finishedAt": finished,
                    "childPid": None,
                })
                atomic_json(CONFIG["leaseFile"], lease)
        finally:
            fcntl.flock(lease_handle.fileno(), fcntl.LOCK_UN)
            lease_handle.close()
    return 0 if phase != "unknown" else 3


sys.exit(main())
'''

STATUS = r'''
import base64, json, os, subprocess, sys

CONFIG = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
attempt = CONFIG["attemptDir"]


def read(name):
    try:
        with open(os.path.join(attempt, name), "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def boot_id():
    try:
        with open("/proc/sys/kernel/random/boot_id", "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def start_time(pid):
    try:
        with open("/proc/%d/stat" % pid, "r", encoding="utf-8") as handle:
            return handle.read().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def unit_state(unit):
    if not unit:
        return None
    env = dict(os.environ)
    env["XDG_RUNTIME_DIR"] = "/run/user/%d" % os.getuid()
    process = subprocess.run(
        ["systemctl", "--user", "show", "-p", "ActiveState", "-p", "SubState", "-p", "Result", unit],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=env,
        check=False,
    )
    values = {}
    for line in process.stdout.decode("utf-8", "replace").splitlines():
        key, _, value = line.partition("=")
        values[key] = value
    return values or None


result = read("result.json")
if result is not None:
    print(json.dumps({"terminal": True, "phase": result.get("phase"), "result": result}))
    sys.exit(0)

state = read("state.json")
dispatch = read("dispatch.json")
input_meta = read("input.json")
if state is None and input_meta is None and dispatch is None:
    print(json.dumps({"terminal": False, "phase": "missing"}))
    sys.exit(0)
if input_meta is None:
    print(json.dumps({"terminal": False, "phase": "interrupted",
                      "reason": "preparation did not publish input.json; not runnable"}))
    sys.exit(0)

unit = unit_state((state or {}).get("unit") or (dispatch or {}).get("unit"))
if state is not None:
    current_boot = boot_id()
    if state.get("bootId") and current_boot and state["bootId"] != current_boot:
        print(json.dumps({"terminal": False, "phase": "unknown",
                          "reason": "node rebooted without a terminal result", "unit": unit}))
        sys.exit(0)
    if state.get("childPid") and start_time(state["childPid"]) == state.get("childStart"):
        print(json.dumps({"terminal": False, "phase": "running", "unit": unit}))
        sys.exit(0)

if unit is not None:
    active = unit.get("ActiveState")
    if active in ("active", "activating", "reloading"):
        print(json.dumps({"terminal": False, "phase": "running", "unit": unit}))
    elif dispatch is None:
        print(json.dumps({"terminal": False, "phase": "prepared", "unit": unit}))
    else:
        print(json.dumps({"terminal": False, "phase": "unknown",
                          "reason": "unit is not active and no result was written", "unit": unit}))
    sys.exit(0)

print(json.dumps({"terminal": False, "phase": "prepared" if dispatch is None else "unknown",
                  "reason": "no unit state available"}))
'''

VERIFY = r'''
import base64, importlib.util, json, sys

CONFIG = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
spec = importlib.util.spec_from_file_location("remote_exec_manifest", CONFIG["manifestModule"])
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)

try:
    value = manifest.verify(CONFIG["root"], CONFIG["manifest"], CONFIG.get("expectInputId"))
except manifest.ManifestError as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
print(json.dumps({"inputId": value}))
'''

ARTIFACT_SCAN = r'''
# Explicit artifacts are not blanket consent to export credentials or agent
# state. Scan before any byte leaves the executor.
import base64, importlib.util, json, os, sys

CONFIG = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


manifest = load("remote_exec_manifest", CONFIG["manifestModule"])
boundary = load("remote_exec_boundary", CONFIG["boundaryModule"])
root = CONFIG["artifacts"]
try:
    entries = manifest.tree_entries(root)
except manifest.ManifestError as error:
    print(str(error), file=sys.stderr)
    sys.exit(2)
for rel in sorted(entries):
    reason = boundary.forbidden_reason(rel)
    if reason:
        print("%r is a %s; refusing to export it as an artifact" % (rel, reason), file=sys.stderr)
        sys.exit(2)
    entry = entries[rel]
    if entry["type"] == "symlink":
        resolved = os.path.normpath(os.path.join(os.path.dirname(rel), entry["target"]))
        reason = boundary.forbidden_reason(resolved)
        if reason:
            print("artifact symlink %r targets a %s; refusing" % (rel, reason), file=sys.stderr)
            sys.exit(2)
value = manifest.build_manifest(root, None)
manifest.write_manifest(value, CONFIG["outputManifest"])
print(json.dumps({"files": sorted(entries), "inputId": value["inputId"]}))
'''

SELECT = r'''
# Compute the selected output: the baseline input plus new source that the
# project's own .gitignore rules admit. `selection.git` is private, empty and
# lives outside work/, so no repository credentials or history are involved.
import base64, importlib.util, json, os, subprocess, sys

CONFIG = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
attempt = CONFIG["attemptDir"]
work = CONFIG["workDir"]
spec = importlib.util.spec_from_file_location("remote_exec_manifest", CONFIG["manifestModule"])
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)

baseline = manifest.load_manifest(CONFIG["inputManifest"])
base_paths = [entry["path"] for entry in baseline["files"]]
selection_spec = importlib.util.spec_from_file_location(
    "remote_exec_selection", CONFIG["selectionModule"])
selection = importlib.util.module_from_spec(selection_spec)
selection_spec.loader.exec_module(selection)
try:
    listed = selection.git_selected(
        work,
        os.path.join(attempt, "selection.git"),
        os.path.join(attempt, "home"),
    )
except selection.SelectionError as error:
    print(str(error), file=sys.stderr)
    sys.exit(2)
sys.path.insert(0, attempt)
import boundary
new = []
for rel in sorted(set(listed) - set(base_paths)):
    try:
        manifest.validate_relpath(rel)
    except manifest.ManifestError as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
    reason = boundary.forbidden_reason(rel)
    if reason:
        print("%r is a %s; refusing to collect it" % (rel, reason), file=sys.stderr)
        sys.exit(2)
    new.append(rel)
present = [p for p in base_paths if os.path.lexists(os.path.join(work, p))]
removed = sorted(set(base_paths) - set(present))
selection = sorted(set(present) | set(new))
value = manifest.build_selection(work, selection, baseline.get("baseRevision"))
manifest.write_manifest(value, CONFIG["outputManifest"])
print(json.dumps({"files": selection, "removed": removed, "outputId": value["inputId"]}))
'''
