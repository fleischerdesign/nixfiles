import json
import os
import subprocess
import tempfile
import unittest
import uuid

from remote_exec import attempt as attempt_module
from remote_exec import transport

from support import RepoFixture


class AttemptTest(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write("tracked.txt", "one\n")
        self.write("other.txt", "two\n")
        self.commit("base")
        self.executor = os.path.join(self.tmp, "executor")
        os.makedirs(self.executor)
        self.transport = transport.LocalTransport()

    def dispatch(self, argv, timeout=60, cwd=".", attempt_id=None):
        capture_dir = attempt_module.capture_to(self.repo)
        self.addCleanup(lambda: transport.cleanup(capture_dir))
        attempt_module.add_verifier(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        attempt = attempt_module.Attempt(
            self.transport, self.executor, "repo", "run", attempt_id or str(uuid.uuid4())
        )
        attempt.prepare()
        self.transport.push_tree(capture_dir, attempt.staging)
        attempt.verify(captured["inputId"])
        attempt.write(
            f"{attempt.staging}/input.json",
            json.dumps({"inputId": captured["inputId"], "attemptId": attempt.attempt_id}),
        )
        attempt.publish()
        result = attempt.run(
            argv=argv,
            cwd=cwd,
            timeout_secs=timeout,
            env={"PATH": os.environ["PATH"]},
            node_id="node-1",
            input_id=captured["inputId"],
        )
        return attempt, captured, result

    def test_successful_command_and_artifact_collection(self):
        attempt, captured, result = self.dispatch(
            [
                "sh",
                "-c",
                'mkdir -p "$REMOTE_EXEC_ARTIFACTS" && '
                'printf ok > "$REMOTE_EXEC_ARTIFACTS/report.txt" && echo hello',
            ]
        )
        self.assertEqual(result["phase"], "succeeded")
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(result["inputId"], captured["inputId"])
        out = os.path.join(self.tmp, "collected")
        collected = attempt.collect(out, with_logs=True)
        self.assertEqual(collected["phase"], "succeeded")
        with open(os.path.join(out, "artifacts", "report.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "ok")
        with open(os.path.join(out, "logs", "stdout.log"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "hello\n")

    def test_failed_command_is_a_terminal_result(self):
        _, _, result = self.dispatch(["sh", "-c", "echo bad >&2; exit 7"])
        self.assertEqual(result["phase"], "failed")
        self.assertEqual(result["exitCode"], 7)

    def test_cwd_escape_is_refused_before_execution(self):
        _, _, result = self.dispatch(["sh", "-c", "touch escaped"], cwd="../..")
        self.assertIsNone(result, "the runner must not execute a command outside the work tree")

    def test_attempt_directory_is_never_reused(self):
        attempt_id = str(uuid.uuid4())
        self.dispatch(["true"], attempt_id=attempt_id)
        attempt = attempt_module.Attempt(self.transport, self.executor, "repo", "run", attempt_id)
        with self.assertRaises(attempt_module.Blocked):
            attempt.prepare()

    def test_unverified_export_is_not_published(self):
        capture_dir = attempt_module.capture_to(self.repo)
        self.addCleanup(lambda: transport.cleanup(capture_dir))
        attempt_module.add_verifier(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        attempt = attempt_module.Attempt(self.transport, self.executor, "repo", "run", str(uuid.uuid4()))
        attempt.prepare()
        self.transport.push_tree(capture_dir, attempt.staging)
        with open(os.path.join(attempt.staging, "work", "tracked.txt"), "w", encoding="utf-8") as handle:
            handle.write("tampered\n")
        with self.assertRaises(attempt_module.Blocked):
            attempt.verify(captured["inputId"])
        self.assertFalse(os.path.exists(attempt.path))
        self.assertFalse(os.path.exists(os.path.join(attempt.staging, "state.json")))

    def test_status_distinguishes_prepared_running_and_unknown(self):
        attempt_id = str(uuid.uuid4())
        attempt = attempt_module.Attempt(self.transport, self.executor, "repo", "run", attempt_id)
        attempt.prepare()
        self.assertEqual(attempt.status()["phase"], "prepared")
        attempt.publish()

        child = subprocess.Popen(["sleep", "30"])
        try:
            with open("/proc/sys/kernel/random/boot_id", encoding="utf-8") as handle:
                boot = handle.read().strip()
            with open(f"/proc/{child.pid}/stat", encoding="utf-8") as handle:
                start = handle.read().rsplit(")", 1)[1].split()[19]
            with open(os.path.join(attempt.path, "state.json"), "w", encoding="utf-8") as handle:
                json.dump(
                    {
                        "phase": "running",
                        "bootId": boot,
                        "childPid": child.pid,
                        "childStart": start,
                    },
                    handle,
                )
            self.assertEqual(attempt.status()["phase"], "running")
        finally:
            child.terminate()
            child.wait(timeout=10)
        self.assertEqual(attempt.status()["phase"], "unknown")

    def test_boot_change_makes_a_live_pid_unknown(self):
        attempt = attempt_module.Attempt(self.transport, self.executor, "repo", "run", str(uuid.uuid4()))
        attempt.prepare()
        attempt.publish()
        with open(os.path.join(attempt.path, "state.json"), "w", encoding="utf-8") as handle:
            json.dump({"phase": "running", "bootId": "other-boot", "childPid": os.getpid()}, handle)
        self.assertEqual(attempt.status()["phase"], "unknown")

    def test_timeout_reports_cancelled_only_after_process_group_exit(self):
        _, _, result = self.dispatch(["sh", "-c", "sleep 30 & wait"], timeout=1)
        self.assertEqual(result["phase"], "cancelled")
        self.assertIn("terminated", result["reason"])

    def test_delta_returns_changes_against_the_recorded_input(self):
        attempt, captured, _ = self.dispatch(
            ["sh", "-c", "printf two > tracked.txt; printf new > new.txt; rm other.txt"]
        )
        out = os.path.join(self.tmp, "collected-delta")
        attempt.collect(out, with_delta=True)
        with open(os.path.join(out, "delta.json"), encoding="utf-8") as handle:
            delta = json.load(handle)
        changes = {entry["path"]: entry["change"] for entry in delta["changes"]}
        self.assertEqual(changes, {"tracked.txt": "modified", "new.txt": "added", "other.txt": "deleted"})
        self.assertEqual(delta["baseInputId"], captured["inputId"])

    def test_delta_applies_only_to_the_exact_base_input(self):
        attempt, captured, _ = self.dispatch(["sh", "-c", "printf two > tracked.txt; printf new > new.txt"])
        out = os.path.join(self.tmp, "collected-apply")
        attempt.collect(out, with_delta=True)
        applied = attempt_module.apply_delta(
            os.path.join(out, "delta.json"), os.path.join(out, "source"), self.repo
        )
        self.assertEqual(applied, {"added": 1, "modified": 1, "deleted": 0})
        with open(os.path.join(self.repo, "tracked.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "two")
        self.assertTrue(os.path.exists(os.path.join(self.repo, "new.txt")))

    def test_conflicting_delta_writes_nothing(self):
        attempt, _, _ = self.dispatch(["sh", "-c", "printf two > tracked.txt"])
        out = os.path.join(self.tmp, "collected-conflict")
        attempt.collect(out, with_delta=True)
        with open(os.path.join(self.repo, "other.txt"), "w", encoding="utf-8") as handle:
            handle.write("local change\n")
        with self.assertRaises(attempt_module.Blocked):
            attempt_module.apply_delta(
                os.path.join(out, "delta.json"), os.path.join(out, "source"), self.repo
            )
        with open(os.path.join(self.repo, "tracked.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "one\n")
