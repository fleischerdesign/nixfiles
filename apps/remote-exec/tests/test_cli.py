import json
import os
import subprocess
import sys
import unittest
import uuid

from support import RepoFixture
from remote_exec import attempt, cli, transport


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
        os.makedirs(self.executor)
        self.inventory = os.path.join(self.tmp, "inventory.json")
        with open(self.inventory, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "schemaVersion": 1,
                    "hosts": {
                        "hom-wrk-01": {
                            "hostType": "workstation",
                            "sshAddress": "10.10.100.20",
                            "architecture": "x86_64",
                        }
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

    def test_capture_and_inventory_commands(self):
        out = os.path.join(self.tmp, "capture")
        captured = self.cli("capture", "--repo", self.repo, "--out", out)
        self.assertEqual(captured.returncode, 0, captured.stderr)
        self.assertIn("inputId", json.loads(captured.stdout))
        inventory = self.cli("--inventory", self.inventory, "inventory")
        self.assertEqual(inventory.returncode, 0, inventory.stderr)
        self.assertEqual(json.loads(inventory.stdout)["hosts"]["hom-wrk-01"]["sshAddress"], "10.10.100.20")

    def test_run_status_and_collect(self):
        attempt_id = str(uuid.uuid4())
        common = [
            "--transport", "local",
            "--remote-root", self.executor,
            "--repo-id", "nixfiles",
            "--run-id", "run-1",
            "--attempt-id", attempt_id,
        ]
        ran = self.cli(
            "run", *common,
            "--repo", self.repo,
            "--node-id", "node-1",
            "--", "sh", "-c",
            'mkdir -p "$REMOTE_EXEC_ARTIFACTS" && printf ok > "$REMOTE_EXEC_ARTIFACTS/x"',
        )
        self.assertEqual(ran.returncode, 0, ran.stderr)
        self.assertEqual(json.loads(ran.stdout)["phase"], "succeeded")

        status = self.cli("status", *common)
        self.assertEqual(status.returncode, 0, status.stderr)
        state = json.loads(status.stdout)
        self.assertTrue(state["terminal"])

        out = os.path.join(self.tmp, "collected")
        collected = self.cli("collect", *common, "--out", out)
        self.assertEqual(collected.returncode, 0, collected.stderr)
        self.assertTrue(os.path.exists(os.path.join(out, "artifacts", "x")))

    def test_failed_command_exit_code_and_unknown_target(self):
        common = [
            "--transport", "local",
            "--remote-root", self.executor,
            "--repo-id", "nixfiles",
            "--run-id", "run-2",
        ]
        failed = self.cli(
            "run", *common,
            "--repo", self.repo,
            "--node-id", "node-1",
            "--", "sh", "-c", "exit 9",
        )
        self.assertEqual(failed.returncode, 1, failed.stderr)

        unknown = self.cli(
            "--inventory", self.inventory,
            "run",
            "--target", "hom-srv-01",
            "--ssh-user", "nobody",
            "--remote-root", self.executor,
            "--repo-id", "nixfiles",
            "--run-id", "run-3",
            "--repo", self.repo,
            "--node-id", "node-1",
            "--", "true",
        )
        self.assertEqual(unknown.returncode, 2)
        self.assertIn("not a declared host", unknown.stderr)

    def test_every_invocation_captures_the_current_source(self):
        def run(run_id, out_name):
            out = os.path.join(self.tmp, out_name)
            ran = self.cli(
                "run",
                "--transport", "local",
                "--remote-root", self.executor,
                "--repo-id", "nixfiles",
                "--run-id", run_id,
                "--repo", self.repo,
                "--node-id", "node-1",
                "--", "sh", "-c", 'cat tracked.txt > "$REMOTE_EXEC_ARTIFACTS/seen"',
            )
            self.assertEqual(ran.returncode, 0, ran.stderr)
            result = json.loads(ran.stdout)
            collected = self.cli(
                "collect",
                "--transport", "local",
                "--remote-root", self.executor,
                "--repo-id", "nixfiles",
                "--run-id", run_id,
                "--attempt-id", result["attemptId"],
                "--out", out,
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

    def test_executor_identity_mismatch_blocks_before_dispatch(self):
        class WrongHost(transport.Transport):
            def preflight(self):
                return {"hostname": "some-other-host", "machine": "x86_64", "path": "/bin"}

        with self.assertRaises(attempt.Blocked):
            cli.check_executor(WrongHost(), "hom-wrk-01", {"architecture": "x86_64"})

        class WrongArchitecture(transport.Transport):
            def preflight(self):
                return {"hostname": "hom-wrk-01", "machine": "aarch64", "path": "/bin"}

        with self.assertRaises(attempt.Blocked):
            cli.check_executor(WrongArchitecture(), "hom-wrk-01", {"architecture": "x86_64"})
