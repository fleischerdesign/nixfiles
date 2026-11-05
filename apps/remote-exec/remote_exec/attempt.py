"""Attempt ownership, dispatch, supervision, reconciliation and collection.

Executor layout (all inside the claimed attempt directory):

    <root>/<repo-id>/<run-id>/<attempt-id>/
        input.json          published last; its presence means "runnable"
        input-files.json    canonical input manifest
        runner.py           supervisor script (runs under user systemd)
        runner-config.json  maybe-sensitive argv/env for the command
        manifest.py boundary.py verify.py
        work/               real copies; writable; build outputs stay here
        home/ tmp/ logs/ artifacts/
        dispatch.json       exclusive single-dispatch claim
        state.json          runner state while the command lives
        result.json         one atomic terminal result

The attempt directory is created with `mkdir`, which is atomic on the executor:
a duplicate request sees it and observes, never stages or runs. `input.json` is
written last, so an interrupted preparation is visible as `interrupted` and is
not runnable. `dispatch.json` uses O_CREAT|O_EXCL, and the systemd unit name is
the attempt id, so the same attempt cannot be dispatched twice.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
import uuid

from . import boundary, manifest, runner, source, transport

ID_PATTERN = __import__("re").compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class Blocked(Exception):
    """Pre-dispatch refusal; no input was published as runnable."""


class UnknownOutcome(Exception):
    """The attempt was dispatched but has no terminal observation."""

    def __init__(self, attempt_id: str, state: dict):
        super().__init__(state.get("reason") or "outcome unknown")
        self.attempt_id = attempt_id
        self.state = state


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
        self.staging = f"{self.path}/.staging"
        # The unit must be unique across the whole attempt identity, not just
        # the attempt id: two runs in different repositories may deliberately
        # reuse an explicit id. Hash the canonical identity to a bounded name.
        identity = "\0".join([self.root, self.repo_id, self.run_id, self.attempt_id])
        self.unit = "remote-exec-" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:24]

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
            "try:\n"
            "    os.mkdir(c['attempt'])\n"
            "except FileExistsError:\n"
            "    print('attempt already exists; observe it with status instead of staging again', file=sys.stderr)\n"
            "    raise SystemExit(1)\n"
            "os.mkdir(c['staging'])\n"
            "with open(os.path.join(c['attempt'],'state.json'),'w',encoding='utf-8') as h:\n"
            "    json.dump({'schemaVersion':2,'phase':'preparing','attemptId':c['id']},h)\n",
            {"attempt": self.path, "staging": self.staging, "id": self.attempt_id},
        )

    def write(self, path: str, text: str) -> None:
        self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "os.makedirs(os.path.dirname(c['path']), exist_ok=True)\n"
            "tmp=c['path']+'.tmp'\n"
            "with open(tmp,'w',encoding='utf-8') as h:\n"
            "    h.write(c['text'])\n"
            "    h.flush(); os.fsync(h.fileno())\n"
            "os.replace(tmp,c['path'])\n",
            {"path": path, "text": text},
        )

    def verify_input(self, input_id: str) -> None:
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

    def publish(self, input_meta: dict) -> None:
        self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "if os.path.exists(os.path.join(c['attempt'],'input.json')):\n"
            "    raise SystemExit('attempt already published: ' + c['attempt'])\n"
            "for name in sorted(os.listdir(c['staging'])):\n"
            "    source=os.path.join(c['staging'],name)\n"
            "    target=os.path.join(c['attempt'],name)\n"
            "    if os.path.exists(target):\n"
            "        raise SystemExit('refusing to overwrite ' + target)\n"
            "    os.replace(source,target)\n"
            "tmp=os.path.join(c['attempt'],'input.json.tmp')\n"
            "with open(tmp,'w',encoding='utf-8') as h:\n"
            "    json.dump(c['input'],h,indent=2,sort_keys=True); h.write('\\n')\n"
            "    h.flush(); os.fsync(h.fileno())\n"
            "os.replace(tmp, os.path.join(c['attempt'],'input.json'))\n"
            "os.rmdir(c['staging'])\n",
            {"attempt": self.path, "staging": self.staging, "input": input_meta},
        )

    def claim_dispatch(self, input_id: str, unit: str | None = None) -> None:
        process = self.transport.run_py(
            "import base64,json,os,sys,time\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "path=os.path.join(c['attempt'],'dispatch.json')\n"
            "try:\n"
            "    fd=os.open(path, os.O_CREAT|os.O_EXCL|os.O_WRONLY, 0o600)\n"
            "except FileExistsError:\n"
            "    print('already-dispatched: reconcile it with status', file=sys.stderr)\n"
            "    raise SystemExit(1)\n"
            "with os.fdopen(fd,'w',encoding='utf-8') as h:\n"
            "    json.dump({'schemaVersion':2,'attemptId':c['id'],'inputId':c['input'],\n"
            "               'unit':c['unit'],'claimedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())},h)\n"
            "    h.flush(); os.fsync(h.fileno())\n",
            {"attempt": self.path, "id": self.attempt_id, "input": input_id, "unit": unit or ""},
            timeout=60,
        )
        if process.returncode == 0:
            return
        message = process.stderr.decode("utf-8", "replace").strip()
        if "already-dispatched" in message:
            raise Blocked("this attempt was already dispatched; reconcile it with status")
        # The claim is a remote write: a lost acknowledgement may still have
        # created it. Unknown, not a pre-dispatch rejection.
        raise transport.TransportError(message or "dispatch claim outcome unknown")

    def status(self, timeout: float = 60) -> dict:
        process = self._py(runner.STATUS, {"attemptDir": self.path}, timeout=timeout)
        return json.loads(process.stdout.decode("utf-8"))

    def dispatch(self, argv: list[str], cwd: str, timeout_secs: int, env: dict, input_id: str) -> dict:
        unit = self.unit if self.transport.supervised else None
        self.write(f"{self.path}/runner.py", runner.RUNNER)
        with open(os.path.join(os.path.dirname(os.path.abspath(boundary.__file__)), "boundary.py"), encoding="utf-8") as handle:
            self.write(f"{self.path}/boundary.py", handle.read())
        self.write(
            f"{self.path}/runner-config.json",
            json.dumps(
                {
                    "attemptDir": self.path,
                    "workDir": f"{self.path}/work",
                    "cwd": cwd,
                    "argv": argv,
                    "env": env,
                    "timeoutSecs": timeout_secs,
                    "attemptId": self.attempt_id,
                    "inputId": input_id,
                    "unit": unit,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
        )
        try:
            self.claim_dispatch(input_id, unit)
        except Blocked:
            raise
        except (transport.TransportError, subprocess.TimeoutExpired) as error:
            raise UnknownOutcome(
                self.attempt_id,
                self._unknown_state(input_id, f"dispatch claim outcome unknown: {error}"),
            ) from error
        try:
            self.transport.supervise(self.path, timeout_secs, unit)
        except (transport.TransportError, subprocess.TimeoutExpired):
            # The unit may still be running. Never replay: the terminal state is
            # whatever `status` can observe.
            pass
        # The unit is owned by systemd, not by this SSH session. Observation is
        # a bounded series of independent reads; losing one does not restart or
        # cancel anything.
        deadline = time.monotonic() + timeout_secs + 120
        last_state: dict | None = None
        while True:
            try:
                state = self.status()
            except (Blocked, transport.TransportError, subprocess.TimeoutExpired) as error:
                raise UnknownOutcome(
                    self.attempt_id,
                    self._unknown_state(input_id, f"attempt was dispatched; reconciliation failed: {error}"),
                ) from error
            if state.get("terminal"):
                return state["result"]
            last_state = state
            # `unknown`, `interrupted` and `missing` will not become terminal by
            # waiting: the unit is gone or never became runnable. Report it now.
            if state.get("phase") in ("unknown", "interrupted", "missing"):
                raise UnknownOutcome(self.attempt_id, state)
            if time.monotonic() >= deadline:
                raise UnknownOutcome(
                    self.attempt_id,
                    self._unknown_state(
                        input_id,
                        "attempt was dispatched; no terminal observation before the deadline",
                    ),
                )
            time.sleep(5)

    def _unknown_state(self, input_id: str | None, reason: str) -> dict:
        return {
            "terminal": False,
            "phase": "unknown",
            "attemptId": self.attempt_id,
            "inputId": input_id,
            "unit": self.unit,
            "reason": reason,
            "recovery": (
                f"remote-exec status --repo-id {self.repo_id} --run-id {self.run_id} "
                f"--attempt-id {self.attempt_id} ..."
            ),
        }

    def cancel(self) -> dict:
        try:
            state = self.status()
        except (Blocked, transport.TransportError, subprocess.TimeoutExpired) as error:
            return self._unknown_state(None, f"cannot observe the attempt: {error}")
        if state.get("terminal"):
            return state
        dispatch = self.read_json("dispatch.json") or {}
        if not self.transport.supervised:
            return state
        unit = dispatch.get("unit") or self.unit
        try:
            self.transport.cancel(unit)
            return self.status()
        except (Blocked, transport.TransportError, subprocess.TimeoutExpired) as error:
            return self._unknown_state(None, f"cancel was requested but could not be confirmed: {error}")

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
        return json.loads(process.stdout.decode("utf-8") or "null")

    def _select_output(self) -> dict:
        process = self._py(
            runner.SELECT,
            {
                "attemptDir": self.path,
                "workDir": f"{self.path}/work",
                "manifestModule": f"{self.path}/manifest.py",
                "inputManifest": f"{self.path}/input-files.json",
                "outputManifest": f"{self.path}/output-files.json",
            },
            timeout=600,
        )
        return json.loads(process.stdout.decode("utf-8"))

    def collect(
        self,
        local_out: str,
        with_logs: bool = False,
        with_artifacts: bool = False,
        with_delta: bool = False,
    ) -> dict:
        local_out = os.path.abspath(local_out)
        if os.path.islink(local_out):
            raise Blocked("collect target is a symlink; refusing to publish into it")
        if os.path.exists(local_out):
            if not os.path.isdir(local_out):
                raise Blocked(f"collect target {local_out} is not a directory")
            if os.listdir(local_out):
                raise Blocked(
                    f"collect target {local_out} is not empty; a fresh destination prevents stale results"
                )
        info = self.read_json("input.json")
        input_files = self.read_json("input-files.json")
        if info is None or input_files is None:
            raise Blocked("attempt has no published input metadata")
        state = self.status()
        if not state.get("terminal"):
            raise Blocked("attempt is not terminal; reconcile it with status before collecting")
        result = state["result"]
        if result.get("inputId") != input_files.get("inputId"):
            raise Blocked("result is not tied to the attempt's recorded input")

        selection = self._select_output()
        output_manifest_text = self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "print(open(os.path.join(c['attempt'],'output-files.json'),encoding='utf-8').read())\n",
            {"attempt": self.path},
        ).stdout.decode("utf-8")
        output_manifest = json.loads(output_manifest_text)
        if output_manifest.get("inputId") != selection["outputId"]:
            raise Blocked("selected output manifest does not match the selection")

        os.makedirs(local_out, exist_ok=True)
        source_dir = os.path.join(local_out, "source")
        os.makedirs(source_dir, exist_ok=True)
        self.transport.pull_paths(f"{self.path}/work", source_dir, selection["files"])
        manifest.write_manifest(output_manifest, os.path.join(local_out, "output-files.json"))
        observed = sorted(manifest.tree_entries(source_dir))
        expected = sorted(entry["path"] for entry in output_manifest["files"])
        if observed != expected:
            raise Blocked(
                "collected selected tree does not match its manifest: "
                f"missing={sorted(set(expected) - set(observed))[:5]} "
                f"unexpected={sorted(set(observed) - set(expected))[:5]}"
            )
        manifest.verify_selection(
            source_dir,
            os.path.join(local_out, "output-files.json"),
            output_manifest["inputId"],
        )

        if with_logs:
            logs_dir = os.path.join(local_out, "logs")
            self.transport.pull_tree(f"{self.path}/logs", logs_dir)
            for name, expected in result.get("logs", {}).items():
                path = os.path.join(logs_dir, f"{name}.log")
                try:
                    digest = manifest.describe(logs_dir, f"{name}.log")
                except FileNotFoundError as error:
                    raise Blocked(f"result names a missing {name} log") from error
                if digest.get("size") != expected.get("size") or digest.get("sha256") != expected.get("sha256"):
                    raise Blocked(f"collected {name} log does not match the result digest")

        if with_artifacts:
            # Scan and manifest on the executor *before* transferring bytes.
            self._py(
                runner.ARTIFACT_SCAN,
                {
                    "artifacts": f"{self.path}/artifacts",
                    "manifestModule": f"{self.path}/manifest.py",
                    "boundaryModule": f"{self.path}/boundary.py",
                    "outputManifest": f"{self.path}/artifacts-files.json",
                },
                timeout=600,
            )
            artifact_manifest_text = self._py(
                "import base64,json,os,sys\n"
                "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
                "print(open(os.path.join(c['attempt'],'artifacts-files.json'),encoding='utf-8').read())\n",
                {"attempt": self.path},
            ).stdout.decode("utf-8")
            artifacts_dir = os.path.join(local_out, "artifacts")
            self.transport.pull_tree(f"{self.path}/artifacts", artifacts_dir)
            artifact_manifest = os.path.join(local_out, "artifacts-files.json")
            with open(artifact_manifest, "w", encoding="utf-8") as handle:
                handle.write(artifact_manifest_text)
            manifest.verify(artifacts_dir, artifact_manifest)

        with open(os.path.join(local_out, "result.json"), "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
            handle.write("\n")
        if with_delta:
            value = source.selection_delta(
                input_files, output_manifest["files"], selection["removed"], self.attempt_id
            )
            with open(os.path.join(local_out, "delta.json"), "w", encoding="utf-8") as handle:
                json.dump(value, handle, indent=2, sort_keys=True)
                handle.write("\n")
        return result


def capture_to(repo: str, extra_paths: tuple[str, ...] = ()) -> str:
    out = tempfile.mkdtemp(prefix="remote-exec-capture-")
    source.capture(repo, out, extra_paths)
    return out


def add_runtime_files(capture_dir: str) -> None:
    """Copy the verifier and its producer implementation into the export."""
    package_dir = os.path.dirname(os.path.abspath(manifest.__file__))
    for name in ("manifest.py", "boundary.py"):
        shutil.copyfile(os.path.join(package_dir, name), os.path.join(capture_dir, name))
    with open(os.path.join(capture_dir, "verify.py"), "w", encoding="utf-8") as handle:
        handle.write(runner.VERIFY)
