"""Attempt layout, dispatch, reconciliation and collection.

An attempt is a directory on the executor:

    <root>/<repo-id>/<run-id>/<attempt-id>/
        input.json          identity of the attempt and its executor
        input-files.json    canonical source manifest
        manifest.py         the verifier's copy of the producer implementation
        verify.py           verifier entry point
        work/               real copies of the exported source (writable)
        home/  tmp/         attempt-local build environment
        logs/               stdout.log, stderr.log
        artifacts/          collected by the command or by `collect`
        state.json          written by the runner while the command lives
        result.json         written once, atomically, when the command ends

Nothing is published under an attempt name until the exported tree verifies
against its manifest; a failed staging directory keeps its name and is never
treated as runnable.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import uuid

from . import manifest, runner, source, transport

ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class Blocked(Exception):
    """Pre-dispatch refusal; no input was published as runnable."""


def valid_id(value: str, what: str) -> str:
    if not ID_PATTERN.match(value or "") or ".." in value:
        raise Blocked(f"{what} {value!r} is not a safe path component")
    return value


def new_attempt_id() -> str:
    return str(uuid.uuid4())


class Attempt:
    def __init__(self, transport_: transport.Transport, root: str, repo_id: str, run_id: str, attempt_id: str):
        self.transport = transport_
        self.root = root.rstrip("/")
        self.repo_id = valid_id(repo_id, "repo id")
        self.run_id = valid_id(run_id, "run id")
        self.attempt_id = valid_id(attempt_id, "attempt id")
        self.path = f"{self.root}/{self.repo_id}/{self.run_id}/{self.attempt_id}"
        self.staging = f"{self.root}/{self.repo_id}/{self.run_id}/.staging-{self.attempt_id}"

    # -- remote primitives -------------------------------------------------
    def _py(self, code: str, args: object, timeout: float | None = 120):
        process = self.transport.run_py(code, args, timeout=timeout)
        if process.returncode != 0:
            raise Blocked(process.stderr.decode("utf-8", "replace").strip() or "remote operation failed")
        return process

    def prepare(self) -> None:
        self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "os.makedirs(os.path.dirname(c['attempt']), exist_ok=True)\n"
            "if os.path.exists(c['attempt']):\n"
            "    raise SystemExit('attempt already exists: ' + c['attempt'])\n"
            "if os.path.exists(c['staging']):\n"
            "    raise SystemExit('staging already exists: ' + c['staging'])\n"
            "os.makedirs(os.path.join(c['staging'], 'work'))\n"
            "os.makedirs(os.path.join(c['staging'], 'logs'))\n"
            "os.makedirs(os.path.join(c['staging'], 'artifacts'))\n",
            {"attempt": self.path, "staging": self.staging},
        )

    def write(self, path: str, text: str) -> None:
        self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "os.makedirs(os.path.dirname(c['path']), exist_ok=True)\n"
            "with open(c['path'],'w',encoding='utf-8') as h:\n"
            "    h.write(c['text'])\n",
            {"path": path, "text": text},
        )

    def publish(self) -> None:
        self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "if os.path.exists(c['attempt']):\n"
            "    raise SystemExit('attempt already exists: ' + c['attempt'])\n"
            "os.rename(c['staging'], c['attempt'])\n",
            {"attempt": self.path, "staging": self.staging},
        )

    def verify(self, input_id: str) -> None:
        self._py(
            runner.VERIFY,
            {
                "root": f"{self.staging}/work",
                "manifest": f"{self.staging}/input-files.json",
                "manifestModule": f"{self.staging}/manifest.py",
                "expectInputId": input_id,
            },
            timeout=600,
        )

    def run(self, argv: list[str], cwd: str, timeout_secs: int, env: dict, node_id: str, input_id: str) -> dict:
        process = self.transport.run_py(
            runner.RUNNER,
            {
                "attemptDir": self.path,
                "workDir": f"{self.path}/work",
                "cwd": cwd,
                "argv": argv,
                "env": env,
                "timeoutSecs": timeout_secs,
                "attemptId": self.attempt_id,
                "inputId": input_id,
                "nodeId": node_id,
            },
            timeout=timeout_secs + 180,
        )
        if process.returncode != 0:
            # The runner exits 3 for an unknown outcome; the result it wrote is
            # still the authority. Only a missing result is a dispatch failure.
            pass
        return self.read_json("result.json")

    def read_json(self, name: str, timeout: float | None = 60) -> dict | None:
        process = self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "p=os.path.join(c['attempt'], c['name'])\n"
            "try:\n"
            "    with open(p,'r',encoding='utf-8') as h: print(h.read())\n"
            "except FileNotFoundError:\n"
            "    print('null')\n",
            {"attempt": self.path, "name": name},
            timeout=timeout,
        )
        value = json.loads(process.stdout.decode("utf-8") or "null")
        return value

    def status(self, timeout: float = 60) -> dict:
        process = self._py(runner.STATUS, {"attemptDir": self.path}, timeout=timeout)
        return json.loads(process.stdout.decode("utf-8"))

    def collect(self, local_out: str, with_logs: bool = False, with_delta: bool = False) -> dict:
        os.makedirs(local_out, exist_ok=True)
        info = self.read_json("input.json")
        input_files = self.read_json("input-files.json")
        result = self.read_json("result.json")
        if info is None or input_files is None:
            raise Blocked("attempt has no published input metadata")
        if result is None:
            raise Blocked("attempt has no terminal result; reconcile it instead of collecting")
        if result.get("inputId") != input_files.get("inputId"):
            raise Blocked("result is not tied to the attempt's recorded input")
        with open(os.path.join(local_out, "result.json"), "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
            handle.write("\n")
        self.transport.pull_tree(f"{self.path}/artifacts", os.path.join(local_out, "artifacts"))
        if with_logs:
            self.transport.pull_tree(f"{self.path}/logs", os.path.join(local_out, "logs"))
        if with_delta:
            pulled = os.path.join(local_out, "source")
            self.transport.pull_tree(f"{self.path}/work", pulled)
            value = source.delta(input_files, pulled, self.attempt_id)
            with open(os.path.join(local_out, "delta.json"), "w", encoding="utf-8") as handle:
                json.dump(value, handle, indent=2, sort_keys=True)
                handle.write("\n")
        return result


def capture_to(repo: str, extra_paths: tuple[str, ...] = ()) -> str:
    """Capture the working tree into a fresh temporary directory."""
    out = tempfile.mkdtemp(prefix="remote-exec-capture-")
    source.capture(repo, out, extra_paths)
    return out


def add_verifier(capture_dir: str) -> None:
    """Copy the verifier and its producer implementation into the export."""
    package_dir = os.path.dirname(os.path.abspath(manifest.__file__))
    shutil.copyfile(os.path.join(package_dir, "manifest.py"), os.path.join(capture_dir, "manifest.py"))
    with open(os.path.join(capture_dir, "verify.py"), "w", encoding="utf-8") as handle:
        handle.write(runner.VERIFY)


def apply_delta(delta_path: str, source_dir: str, target_repo: str) -> dict:
    """Apply a collected delta only to the exact base input it names.

    The target is re-captured through the same source rules; if its inputId
    differs from `baseInputId` the delta conflicts and nothing is written.
    """
    with open(delta_path, "r", encoding="utf-8") as handle:
        value = json.load(handle)
    probe = tempfile.mkdtemp(prefix="remote-exec-base-")
    try:
        current = source.capture(target_repo, probe)
    finally:
        shutil.rmtree(probe, ignore_errors=True)
    if current["inputId"] != value["baseInputId"]:
        raise Blocked(
            "delta conflicts with the target: base input "
            f"{value['baseInputId']} is not the current input {current['inputId']}"
        )
    applied = {"added": 0, "modified": 0, "deleted": 0}
    for change in value["changes"]:
        rel = manifest.validate_relpath(change["path"])
        destination = os.path.join(target_repo, rel)
        if change["change"] == "deleted":
            if os.path.lexists(destination):
                os.unlink(destination)
            applied["deleted"] += 1
            continue
        origin = os.path.join(source_dir, rel)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        if change["type"] == "symlink":
            target = manifest.validate_symlink(rel, change["target"])
            if os.path.lexists(destination):
                os.unlink(destination)
            os.symlink(target, destination)
        elif change["type"] == "file":
            shutil.copyfile(origin, destination)
            os.chmod(destination, 0o755 if change["mode"] == manifest.EXEC_MODE else 0o644)
        else:
            raise Blocked(f"delta entry {rel} has unsupported type {change['type']!r}")
        applied[change["change"]] += 1
    return applied
