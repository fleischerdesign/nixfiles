"""Self-contained scripts executed on the executor.

The source is shipped over stdin, so the executor needs Python 3 but not this
package. Keeping the runner separate from the control process is what makes a
lost connection an *unknown* attempt instead of a lost result: the runner owns
the child process group and writes its terminal state itself.
"""

RUNNER = r'''
import base64, hashlib, json, os, platform, signal, subprocess, sys, time, uuid

CONFIG = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))


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
            fields = handle.read().rsplit(")", 1)[1].split()
        return fields[19]
    except (OSError, IndexError):
        return None


def digest(path):
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
    if work != attempt and not work.startswith(attempt + os.sep):
        raise SystemExit("work directory escapes the attempt directory")
    cwd = os.path.realpath(os.path.join(work, CONFIG.get("cwd") or "."))
    if cwd != work and not cwd.startswith(work + os.sep):
        raise SystemExit("cwd escapes the exported work tree")
    if not os.path.isdir(cwd):
        raise SystemExit("cwd does not exist in the exported work tree")

    logs = os.path.join(attempt, "logs")
    os.makedirs(logs, exist_ok=True)
    os.makedirs(os.path.join(attempt, "artifacts"), exist_ok=True)
    home = os.path.join(attempt, "home")
    os.makedirs(home, exist_ok=True)

    env = dict(CONFIG.get("env") or {})
    env.setdefault("PATH", "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin")
    env.setdefault("HOME", home)
    env.setdefault("LANG", "C.UTF-8")
    env.setdefault("TMPDIR", os.path.join(attempt, "tmp"))
    env.setdefault("REMOTE_EXEC_ATTEMPT", attempt)
    env.setdefault("REMOTE_EXEC_ARTIFACTS", os.path.join(attempt, "artifacts"))
    os.makedirs(env["TMPDIR"], exist_ok=True)

    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    state = {
        "schemaVersion": 1,
        "phase": "running",
        "attemptId": CONFIG["attemptId"],
        "inputId": CONFIG["inputId"],
        "bootId": boot_id(),
        "runnerPid": os.getpid(),
        "startedAt": started,
    }
    atomic_json(os.path.join(attempt, "state.json"), state)

    stdout_path = os.path.join(logs, "stdout.log")
    stderr_path = os.path.join(logs, "stderr.log")
    phase = "failed"
    reason = None
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
        try:
            code = child.wait(timeout=CONFIG.get("timeoutSecs"))
            phase = "succeeded" if code == 0 else "failed"
        except subprocess.TimeoutExpired:
            code = None
            # Termination is only "cancelled" when the whole owned process group is gone.
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
                    code = None
            # A terminated grandchild can stay visible as a zombie for a moment.
            # Confirm absence over a bounded window instead of one sample.
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
                reason = "timeout; owned process group confirmed terminated"
            else:
                phase = "unknown"
                reason = "process group survived cancellation; outcome unknown"

    finished = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    result = {
        "schemaVersion": 1,
        "attemptId": CONFIG["attemptId"],
        "inputId": CONFIG["inputId"],
        "nodeId": CONFIG.get("nodeId"),
        "command": CONFIG["argv"],
        "startedAt": started,
        "finishedAt": finished,
        "exitCode": None if code is None else code,
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
    atomic_json(os.path.join(attempt, "result.json"), result)
    state["phase"] = phase
    atomic_json(os.path.join(attempt, "state.json"), state)
    return 0 if phase != "unknown" else 3


sys.exit(main())
'''

STATUS = r'''
import base64, json, os, sys

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


result = read("result.json")
state = read("state.json")
if result is not None:
    print(json.dumps({"terminal": True, "phase": result.get("phase"), "result": result}))
elif state is None:
    print(json.dumps({"terminal": False, "phase": "prepared"}))
else:
    current_boot = boot_id()
    if state.get("bootId") and current_boot and state["bootId"] != current_boot:
        print(json.dumps({"terminal": False, "phase": "unknown",
                          "reason": "node rebooted without a terminal result"}))
    elif state.get("childPid") and start_time(state["childPid"]) == state.get("childStart"):
        print(json.dumps({"terminal": False, "phase": "running"}))
    else:
        print(json.dumps({"terminal": False, "phase": "unknown",
                          "reason": "no terminal result and the recorded process is gone"}))
'''

VERIFY = r'''
# Shipped inside the attempt. `manifest.py` in the attempt directory is the
# exact implementation the Gateway used, so verifier and producer cannot
# disagree about a path, a mode or a digest.
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
