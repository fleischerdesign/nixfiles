"""Reusable task workspaces on an executor.

A workspace is bound to the real repository identity (the canonical Git common
directory), the declared executor root/target/account and the caller's label.
It is a persistent task directory: `work/` keeps source and build outputs,
`home/` keeps tool-native state, and `state/` holds ownership metadata outside
the work tree. Fresh attempts (no workspace id) keep the original one-shot
layout and semantics.

A lease serialises a workspace: one attempt syncs and runs at a time, and a
lease that cannot be proven terminal is never taken over silently. A crash
leaves the incomplete marker or the non-terminal lease that `workspace-status`,
`cancel`, `workspace-reset` and `workspace-prune` reason about.

The workspace is a convenience, not a hermetic build proof. Retained build
output is only valid to the build tool that produced it; `--clean` is the
explicit way to ask for a fresh work and HOME state inside the same workspace.
"""

from __future__ import annotations

import hashlib
import json
import os
import uuid

from . import attempt as attempt_module
from . import manifest, runner, source, transport, workspace_scripts

SCHEMA_VERSION = 1


def workspace_key(
    root: str,
    target: str,
    user: str | None,
    repo_id: str,
    label: str,
    repo_identity: str,
) -> str:
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "root": root.rstrip("/"),
        "target": target,
        "user": user,
        "repoId": repo_id,
        "label": label,
        "repoIdentity": repo_identity,
    }
    data = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(data.encode("utf-8")).hexdigest()[:32]


class Workspace:
    def __init__(
        self,
        transport_: transport.Transport,
        root: str,
        target: str,
        user: str | None,
        repo_id: str,
        label: str,
        repo_identity: str,
    ):
        self.transport = transport_
        self.root = root.rstrip("/")
        self.target = target
        self.user = user
        self.repo_id = attempt_module.valid_id(repo_id, "repo id")
        self.label = attempt_module.valid_id(label, "workspace id")
        self.repo_identity = repo_identity
        self.key = workspace_key(root, target, user, self.repo_id, self.label, repo_identity)
        self.path = f"{self.root}/workspaces/{self.key}"

    def _py(self, code: str, args: object, timeout: float | None = 120):
        process = self.transport.run_py(code, args, timeout=timeout)
        if process.returncode != 0:
            raise attempt_module.Blocked(
                process.stderr.decode("utf-8", "replace").strip() or "workspace operation failed"
            )
        return process

    def _binding(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "repoId": self.repo_id,
            "repoIdentity": self.repo_identity,
            "target": self.target,
            "user": self.user,
            "root": self.root,
        }

    def prepare(self, attempt_id: str, unit: str | None, clean: bool = False) -> dict:
        configuration = dict(self._binding())
        configuration.update(
            {
                "workspace": self.path,
                "attempt": self.attempt_path(attempt_id),
                "staging": self.staging_path(attempt_id),
                "attemptId": attempt_id,
                "unit": unit,
                "clean": clean,
            }
        )
        process = self._py(workspace_scripts.PREPARE, configuration, timeout=120)
        return json.loads(process.stdout.decode("utf-8"))

    def sync(
        self,
        attempt_id: str,
        input_id: str,
        input_manifest: str,
        manifest_module: str,
        version: str | None = None,
        payload_file: str | None = None,
    ) -> dict:
        staging = self.staging_path(attempt_id)
        process = self._py(
            workspace_scripts.SYNC,
            {
                "workspace": self.path,
                "attempt": self.attempt_path(attempt_id),
                "stagingWork": f"{staging}/work",
                "inputManifest": input_manifest,
                "manifestModule": manifest_module,
                "attemptId": attempt_id,
                "inputId": input_id,
                "version": version or str(uuid.uuid4()),
                "payloadFile": payload_file,
            },
            timeout=900,
        )
        return json.loads(process.stdout.decode("utf-8"))

    def plan(self, attempt_id: str, input_id: str, input_manifest: str, manifest_module: str) -> dict:
        """Compare the captured input with this workspace's last managed state.

        Runs under the workspace lock and the attempt's lease. Only returns what
        needs data; SYNC still verifies the whole resulting tree.
        """
        staging = self.staging_path(attempt_id)
        payload_file = f"{staging}/payload.json"
        process = self._py(
            workspace_scripts.PLAN,
            {
                "workspace": self.path,
                "attempt": self.attempt_path(attempt_id),
                "stagingWork": f"{staging}/work",
                "inputManifest": input_manifest,
                "manifestModule": manifest_module,
                "attemptId": attempt_id,
                "inputId": input_id,
                "payloadFile": payload_file,
            },
            timeout=900,
        )
        value = json.loads(process.stdout.decode("utf-8"))
        value["payloadFile"] = payload_file
        return value

    def attempt_path(self, attempt_id: str) -> str:
        return f"{self.path}/attempts/{attempt_id}"

    def staging_path(self, attempt_id: str) -> str:
        return f"{self.path}/staging/{attempt_id}"

    def snoop(self) -> dict:
        process = self._py(workspace_scripts.SNOOP, {"workspace": self.path}, timeout=120)
        return json.loads(process.stdout.decode("utf-8"))

    def complete_lease(
        self,
        attempt_id: str,
        phase: str = "terminal",
        result_phase: str | None = None,
        abandon: bool = False,
        reason: str | None = None,
    ) -> dict:
        process = self._py(
            workspace_scripts.COMPLETE_LEASE,
            {
                "workspace": self.path,
                "attemptId": attempt_id,
                "phase": phase,
                "resultPhase": result_phase,
                "abandon": abandon,
                "reason": reason,
            },
            timeout=60,
        )
        return json.loads(process.stdout.decode("utf-8"))

    def reset(self, clean_home: bool = False, force: bool = False) -> dict:
        process = self._py(
            workspace_scripts.RESET,
            {
                "workspace": self.path,
                "cleanHome": clean_home,
                "force": force,
            },
            timeout=900,
        )
        return json.loads(process.stdout.decode("utf-8"))

    def prune(self, apply: bool = False, keep: int = 10, max_age_days: float = 14) -> dict:
        process = self._py(
            workspace_scripts.PRUNE,
            {
                "workspace": self.path,
                "apply": apply,
                "keep": keep,
                "cutoff": int(__import__("time").time() - max_age_days * 86400),
            },
            timeout=900,
        )
        return json.loads(process.stdout.decode("utf-8"))

    def list_workspaces(self) -> list[dict]:
        process = self._py(workspace_scripts.LIST_WORKSPACES, {"root": self.root}, timeout=120)
        return json.loads(process.stdout.decode("utf-8"))["workspaces"]

    def remove(self, apply: bool = False, max_age_days: float = 14) -> dict:
        cutoff = int(__import__("time").time() - max_age_days * 86400)
        process = self._py(
            workspace_scripts.REMOVE_WORKSPACE,
            {"root": self.root, "workspace": self.path, "apply": apply, "cutoff": cutoff},
            timeout=900,
        )
        return json.loads(process.stdout.decode("utf-8"))


class WorkspaceAttempt(attempt_module.Attempt):
    """One attempt inside a reusable workspace.

    The attempt directory, logs, artifacts and source snapshot stay immutable;
    only the workspace `work/` and `home/` are shared across attempts.
    """

    def __init__(self, transport_: transport.Transport, workspace: Workspace, attempt_id: str):
        self.transport = transport_
        self.workspace = workspace
        self.root = workspace.root
        self.repo_id = workspace.repo_id
        self.run_id = workspace.label
        self.attempt_id = attempt_module.valid_id(attempt_id, "attempt id")
        self.path = workspace.attempt_path(self.attempt_id)
        self.staging = workspace.staging_path(self.attempt_id)
        identity = "\0".join(
            [self.root, "workspace", workspace.key, self.attempt_id]
        )
        self.unit = "remote-exec-" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:24]
        self.clean = False

    @property
    def work_dir(self) -> str:
        return f"{self.workspace.path}/work"

    @property
    def home_dir(self) -> str:
        return f"{self.workspace.path}/home"

    def prepare(self, clean: bool = False) -> None:
        self.clean = clean
        unit = self.unit if self.transport.supervised else None
        self.workspace.prepare(self.attempt_id, unit, clean=clean)

    def publish(self, input_meta: dict) -> None:
        """Publish attempt metadata without moving the shared work tree."""
        self._py(
            "import base64,json,os,sys\n"
            "import shutil\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "attempt=c['attempt']; staging=c['staging']\n"
            "if os.path.exists(os.path.join(attempt,'input.json')):\n"
            "    raise SystemExit('attempt already published: ' + attempt)\n"
            "for name in sorted(os.listdir(staging)):\n"
            "    if name == 'work':\n"
            "        continue\n"
            "    source=os.path.join(staging,name)\n"
            "    target=os.path.join(attempt,name)\n"
            "    if os.path.exists(target):\n"
            "        raise SystemExit('refusing to overwrite ' + target)\n"
            "    os.replace(source,target)\n"
            "tmp=os.path.join(attempt,'input.json.tmp')\n"
            "with open(tmp,'w',encoding='utf-8') as h:\n"
            "    json.dump(c['input'],h,indent=2,sort_keys=True); h.write('\\n')\n"
            "    h.flush(); os.fsync(h.fileno())\n"
            "os.replace(tmp, os.path.join(attempt,'input.json'))\n"
            "shutil.rmtree(os.path.join(staging,'work'), ignore_errors=False)\n"
            "os.rmdir(staging)\n",
            {"attempt": self.path, "staging": self.staging, "input": input_meta},
        )

    def publish_failed(self) -> None:
        """Mark an attempt that never reached publication as interrupted."""
        try:
            self._py(
                "import base64,json,os,shutil,sys\n"
                "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
                "staging=os.path.realpath(c['staging'])\n"
                "workspace=os.path.realpath(c['workspace'])\n"
                "if not staging.startswith(workspace + os.sep):\n"
                "    raise SystemExit('staging escapes the workspace')\n"
                "shutil.rmtree(staging, ignore_errors=True)\n",
                {"staging": self.staging, "workspace": self.workspace.path},
                timeout=120,
            )
        except (attempt_module.Blocked, transport.TransportError):
            pass

    def runner_extra(self) -> dict:
        return {
            "workspaceDir": self.workspace.path,
            "homeDir": self.workspace.path + "/home",
            "leaseFile": self.workspace.path + "/state/lease.json",
            "finalizeScript": self.path + "/finalize.py",
            "finalizeConfig": self.path + "/finalize-config.json",
        }

    def dispatch_files(self) -> dict[str, str]:
        configuration = {
            "attemptDir": self.path,
            "workDir": self.work_dir,
            "inputManifest": f"{self.path}/input-files.json",
            "manifestModule": f"{self.path}/manifest.py",
            "boundaryModule": f"{self.path}/boundary.py",
            "snapshotDir": f"{self.path}/snapshot",
            "outputManifest": f"{self.path}/output-files.json",
            "managedFile": f"{self.workspace.path}/state/managed.json",
        }
        return {
            "finalize.py": workspace_scripts.FINALIZE,
            "finalize-config.json": json.dumps(configuration, indent=2, sort_keys=True) + "\n",
        }

    def collect(
        self,
        local_out: str,
        with_logs: bool = False,
        with_artifacts: bool = False,
        with_delta: bool = False,
    ) -> dict:
        local_out = os.path.abspath(local_out)
        if os.path.islink(local_out):
            raise attempt_module.Blocked("collect target is a symlink; refusing to publish into it")
        if os.path.exists(local_out):
            if not os.path.isdir(local_out):
                raise attempt_module.Blocked(f"collect target {local_out} is not a directory")
            if os.listdir(local_out):
                raise attempt_module.Blocked(
                    f"collect target {local_out} is not empty; a fresh destination prevents stale results"
                )
        info = self.read_json("input.json")
        input_files = self.read_json("input-files.json")
        if info is None or input_files is None:
            raise attempt_module.Blocked("attempt has no published input metadata")
        state = self.status()
        if not state.get("terminal"):
            raise attempt_module.Blocked("attempt is not terminal; reconcile it with status before collecting")
        result = state["result"]
        if result.get("inputId") != input_files.get("inputId"):
            raise attempt_module.Blocked("result is not tied to the attempt's recorded input")
        output = result.get("output") or {}
        if output.get("status") != "ok":
            raise attempt_module.Blocked(
                "this attempt has no immutable source snapshot ("
                + (output.get("error") or "snapshot was not produced")
                + "); its workspace has moved on, so collecting source would be stale"
            )
        output_manifest_text = self._py(
            "import base64,json,os,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "print(open(os.path.join(c['attempt'],'output-files.json'),encoding='utf-8').read())\n",
            {"attempt": self.path},
        ).stdout.decode("utf-8")
        output_manifest = json.loads(output_manifest_text)
        if output_manifest.get("inputId") != output.get("inputId"):
            raise attempt_module.Blocked("snapshot manifest does not match the result receipt")

        expected = sorted(entry["path"] for entry in output_manifest["files"])
        os.makedirs(local_out, exist_ok=True)
        source_dir = os.path.join(local_out, "source")
        os.makedirs(source_dir, exist_ok=True)
        self.transport.pull_paths(f"{self.path}/snapshot", source_dir, expected)
        manifest.write_manifest(output_manifest, os.path.join(local_out, "output-files.json"))
        observed = sorted(manifest.tree_entries(source_dir))
        if observed != expected:
            raise attempt_module.Blocked(
                "collected snapshot does not match its manifest: "
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
            for name, digest_expected in result.get("logs", {}).items():
                path = os.path.join(logs_dir, f"{name}.log")
                try:
                    digest = manifest.describe(logs_dir, f"{name}.log")
                except FileNotFoundError as error:
                    raise attempt_module.Blocked(f"result names a missing {name} log") from error
                if (
                    digest.get("size") != digest_expected.get("size")
                    or digest.get("sha256") != digest_expected.get("sha256")
                ):
                    raise attempt_module.Blocked(f"collected {name} log does not match the result digest")

        if with_artifacts:
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
            baseline = {entry["path"] for entry in input_files["files"]}
            present = set(expected)
            value = source.selection_delta(
                input_files,
                output_manifest["files"],
                sorted(baseline - present),
                self.attempt_id,
            )
            with open(os.path.join(local_out, "delta.json"), "w", encoding="utf-8") as handle:
                json.dump(value, handle, indent=2, sort_keys=True)
                handle.write("\n")
        return result
