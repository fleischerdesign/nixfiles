import json
import os
import subprocess
import sys
import threading
import unittest
import uuid
from contextlib import redirect_stdout
from io import StringIO

from support import RepoFixture
from remote_exec import attempt, cli, transport
from unittest import mock


def command() -> list[str]:
    value = os.environ.get("REMOTE_EXEC_BIN")
    if value:
        return [value]
    return [sys.executable, "-m", "remote_exec"]


class CliTest(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write("tracked.txt", "one\n")
        self.commit("base")
        self.executor = os.path.join(self.tmp, "executor")
        os.makedirs(self.executor, mode=0o700)
        self.inventory = os.path.join(self.tmp, "inventory.json")
        with open(self.inventory, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "schemaVersion": 2,
                    "hosts": {
                        "hom-wrk-01": {
                            "hostType": "workstation",
                            "sshAddress": "10.10.100.20",
                            "architecture": "x86_64",
                            "executor": {
                                "user": "remote-exec",
                                "root": "/var/lib/remote-exec",
                                "hostKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest",
                                "runtimePath": "/run/current-system/sw/bin",
                            },
                        },
                        "hom-srv-01": {
                            "hostType": "server",
                            "sshAddress": "10.10.100.10",
                            "architecture": "x86_64",
                            "executor": {},
                        },
                    },
                },
                handle,
            )

    def cli(self, *args, env=None):
        environment = dict(os.environ)
        environment.update(env or {})
        return subprocess.run(
            command() + list(args),
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def local_common(self, run_id, attempt_id=None):
        args = [
            "--transport", "local",
            "--remote-root", self.executor,
            "--repo-id", "nixfiles",
            "--run-id", run_id,
        ]
        if attempt_id:
            args += ["--attempt-id", attempt_id]
        return args

    def test_capture_and_inventory_commands(self):
        out = os.path.join(self.tmp, "capture")
        captured = self.cli("capture", "--repo", self.repo, "--out", out)
        self.assertEqual(captured.returncode, 0, captured.stderr)
        self.assertIn("inputId", json.loads(captured.stdout))
        inventory = self.cli("--inventory", self.inventory, "inventory")
        self.assertEqual(inventory.returncode, 0, inventory.stderr)
        self.assertEqual(json.loads(inventory.stdout)["hosts"]["hom-wrk-01"]["executor"]["user"], "remote-exec")

    def test_host_without_an_executor_declaration_is_refused(self):
        refused = self.cli(
            "--inventory", self.inventory,
            "run",
            "--target", "hom-srv-01",
            "--identity", "/does/not/exist",
            "--remote-root", "/var/lib/remote-exec",
            "--repo-id", "nixfiles",
            "--run-id", "run-x",
            "--repo", self.repo,
            "--", "true",
        )
        self.assertEqual(refused.returncode, 2)
        self.assertIn("no declared executor", refused.stderr)

    def test_run_status_and_collect(self):
        attempt_id = str(uuid.uuid4())
        common = self.local_common("run-1", attempt_id)
        ran = self.cli(
            "run", *common,
            "--repo", self.repo,
            "--", "sh", "-c",
            'mkdir -p "$REMOTE_EXEC_ARTIFACTS" && printf ok > "$REMOTE_EXEC_ARTIFACTS/x"',
        )
        self.assertEqual(ran.returncode, 0, ran.stderr)
        self.assertEqual(json.loads(ran.stdout)["phase"], "succeeded")

        status = self.cli("status", *common)
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertTrue(json.loads(status.stdout)["terminal"])

        out = os.path.join(self.tmp, "collected")
        collected = self.cli("collect", *common, "--out", out, "--artifacts")
        self.assertEqual(collected.returncode, 0, collected.stderr)
        self.assertTrue(os.path.exists(os.path.join(out, "artifacts", "x")))

    def test_failed_command_exit_code(self):
        failed = self.cli(
            "run", *self.local_common("run-2"),
            "--repo", self.repo,
            "--", "sh", "-c", "exit 9",
        )
        self.assertEqual(failed.returncode, 1, failed.stderr)

    def test_every_invocation_captures_the_current_source(self):
        def run(run_id, out_name):
            out = os.path.join(self.tmp, out_name)
            ran = self.cli(
                "run", *self.local_common(run_id),
                "--repo", self.repo,
                "--", "sh", "-c", 'cat tracked.txt > "$REMOTE_EXEC_ARTIFACTS/seen"',
            )
            self.assertEqual(ran.returncode, 0, ran.stderr)
            result = json.loads(ran.stdout)
            attempt_id = result["attemptId"]
            collected = self.cli(
                "collect", *self.local_common(run_id, attempt_id), "--out", out, "--artifacts"
            )
            self.assertEqual(collected.returncode, 0, collected.stderr)
            with open(os.path.join(out, "artifacts", "seen"), encoding="utf-8") as handle:
                return result["inputId"], handle.read()

        first_input, first_seen = run("run-a", "first")
        self.write("tracked.txt", "changed between invocations\n")
        self.write("new.txt", "untracked\n")
        second_input, second_seen = run("run-b", "second")

        self.assertNotEqual(first_input, second_input)
        self.assertEqual(first_seen, "one\n")
        self.assertEqual(second_seen, "changed between invocations\n")

    def test_concurrent_same_attempt_dispatches_once(self):
        attempt_id = str(uuid.uuid4())
        results = []

        def invoke(_):
            results.append(
                self.cli(
                    "run", *self.local_common("run-race", attempt_id),
                    "--repo", self.repo,
                    "--", "sh", "-c", 'mkdir -p "$REMOTE_EXEC_ARTIFACTS" && echo x >> "$REMOTE_EXEC_ARTIFACTS/count"',
                )
            )

        threads = [threading.Thread(target=invoke, args=(index,)) for index in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        codes = sorted(result.returncode for result in results)
        self.assertEqual(codes, [0, 2], [result.stderr for result in results])
        count = os.path.join(
            self.executor, "nixfiles", "run-race", attempt_id, "artifacts", "count"
        )
        with open(count, encoding="utf-8") as handle:
            self.assertEqual(len(handle.readlines()), 1)

    def test_executor_identity_mismatch_blocks_before_dispatch(self):
        class WrongHost(transport.Transport):
            def preflight(self, root):
                return {
                    "hostname": "some-other-host",
                    "machine": "x86_64",
                    "user": "remote-exec",
                    "uid": 1000,
                    "root": root,
                    "rootOwner": 1000,
                    "rootWritable": True,
                }

        with self.assertRaises(attempt.Blocked):
            cli.check_executor(
                WrongHost(), "hom-wrk-01", {"architecture": "x86_64"},
                {"user": "remote-exec", "root": "/x"}, "/x",
            )

        class RootUser(transport.Transport):
            def preflight(self, root):
                return {
                    "hostname": "hom-wrk-01",
                    "machine": "x86_64",
                    "user": "root",
                    "uid": 0,
                    "root": root,
                    "rootOwner": 0,
                    "rootWritable": True,
                }

        with self.assertRaises(attempt.Blocked):
            cli.check_executor(
                RootUser(), "hom-wrk-01", {"architecture": "x86_64"},
                {"user": "root", "root": "/x"}, "/x",
            )

    def test_root_account_is_refused_by_identity(self):
        refused = self.cli(
            "--inventory", self.inventory,
            "run",
            "--target", "hom-wrk-01",
            "--identity", "/does/not/exist",
            "--remote-root", "/var/lib/remote-exec",
            "--repo-id", "nixfiles",
            "--run-id", "run-root",
            "--repo", self.repo,
            "--", "true",
        )
        self.assertEqual(refused.returncode, 2)
        self.assertIn("identity file", refused.stderr)

    def test_unknown_outcome_is_exit_three(self):
        unknown = attempt.UnknownOutcome(
            "attempt-x",
            {
                "terminal": False,
                "phase": "unknown",
                "attemptId": "attempt-x",
                "inputId": "input-x",
                "unit": "remote-exec-x",
                "reason": "connection lost after dispatch",
                "recovery": "remote-exec status ...",
            },
        )
        buffer = StringIO()
        with mock.patch.object(attempt.Attempt, "dispatch", side_effect=unknown), redirect_stdout(buffer):
            code = cli.main(
                [
                    "run",
                    *self.local_common("run-unknown"),
                    "--repo", self.repo,
                    "--", "true",
                ]
            )
        self.assertEqual(code, 3)
        printed = json.loads(buffer.getvalue())
        self.assertEqual(printed["phase"], "unknown")
        self.assertEqual(printed["attemptId"], "attempt-x")

    def test_run_reports_diagnostics_and_preserves_remote_exit_code(self):
        state_home = os.path.join(self.tmp, "state")
        common = self.local_common("run-diagnostics")
        ran = self.cli(
            "run", *common,
            "--repo", self.repo,
            "--", "sh", "-c", "echo out; echo err >&2; exit 4",
            env={"XDG_STATE_HOME": state_home},
        )
        self.assertEqual(ran.returncode, 1, ran.stderr)
        printed = json.loads(ran.stdout)
        self.assertEqual(printed["exitCode"], 4)
        self.assertIn("out", printed["diagnostics"]["stdoutPreview"])
        self.assertIn("err", printed["diagnostics"]["stderrPreview"])
        self.assertTrue(os.path.isdir(printed["diagnostics"]["logsDir"]))

    def test_checkpoint_and_verify_source_commands(self):
        self.write("tracked.txt", "dirty\n")
        checked = self.cli("checkpoint", "--repo", self.repo)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        receipt = json.loads(checked.stdout)
        self.assertTrue(receipt["checkpoint"]["ref"].startswith("refs/remote-exec/checkpoints/"))
        verified = self.cli(
            "verify-source", "--repo", self.repo, "--expect-input-id", receipt["inputId"]
        )
        self.assertEqual(verified.returncode, 0, verified.stderr)
        mismatch = self.cli(
            "verify-source", "--repo", self.repo, "--expect-input-id", "0" * 64
        )
        self.assertEqual(mismatch.returncode, 2)
        self.assertIn("does not match", mismatch.stderr)

    def test_diagnostic_timeout_keeps_terminal_exit_code_with_json_receipt(self):
        terminal = {
            "schemaVersion": 2,
            "phase": "failed",
            "exitCode": 7,
            "inputId": "input-x",
            "attemptId": "attempt-x",
        }
        timeout = subprocess.TimeoutExpired(cmd="ssh", timeout=5)
        buffer = StringIO()
        with mock.patch.object(
            attempt.Attempt, "dispatch", return_value=terminal
        ), mock.patch.object(
            attempt.Attempt, "diagnostics", side_effect=timeout
        ), redirect_stdout(buffer):
            code = cli.main(
                [
                    "run",
                    *self.local_common("run-diag-timeout"),
                    "--repo", self.repo,
                    "--", "sh", "-c", "exit 7",
                ]
            )
        self.assertEqual(code, 1)
        printed = json.loads(buffer.getvalue())
        self.assertEqual(printed["phase"], "failed")
        self.assertEqual(printed["exitCode"], 7)
        self.assertEqual(printed["diagnostics"]["status"], "unavailable")
        self.assertIn("error", printed["diagnostics"])
        self.assertNotIn("logsDir", printed["diagnostics"])

    def test_workspace_cli_reuse_status_collect_reset_and_prune(self):
        common = [
            "--transport", "local",
            "--remote-root", self.executor,
            "--repo-id", "nixfiles",
            "--workspace-id", "task",
            "--repo", self.repo,
        ]
        first = self.cli(
            "run", *common, "--run-id", "run-a",
            "--", "sh", "-c", 'echo first > generated.txt; echo cache > "$HOME/state"',
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        first_result = json.loads(first.stdout)
        second = self.cli(
            "run", *common, "--run-id", "run-b",
            "--", "sh", "-c", 'echo second > generated.txt; cat "$HOME/state"',
        )
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout and json.loads(second.stdout)["output"]["status"], "ok")

        status = self.cli("workspace-status", *common)
        self.assertEqual(status.returncode, 0, status.stderr)
        report = json.loads(status.stdout)
        self.assertTrue(report["exists"])
        self.assertEqual(report["lease"]["phase"], "terminal")

        out = os.path.join(self.tmp, "workspace-collected")
        collected = self.cli(
            "collect", *common, "--run-id", "run-a",
            "--attempt-id", first_result["attemptId"], "--out", out,
        )
        self.assertEqual(collected.returncode, 0, collected.stderr)
        with open(os.path.join(out, "source", "generated.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "first\n")

        pruned = self.cli(
            "workspace-prune", *common, "--keep", "0", "--max-age-days", "0"
        )
        self.assertEqual(pruned.returncode, 0, pruned.stderr)
        self.assertIn("dryRun", pruned.stdout)

        reset = self.cli("workspace-reset", *common)
        self.assertEqual(reset.returncode, 0, reset.stderr)
        self.assertTrue(json.loads(reset.stdout)["reset"])

    def test_clean_requires_a_workspace(self):
        refused = self.cli(
            "run", *self.local_common("run-clean"), "--clean",
            "--repo", self.repo, "--", "true",
        )
        self.assertEqual(refused.returncode, 2)
        self.assertIn("--clean", refused.stderr)
