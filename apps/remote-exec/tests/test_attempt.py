import json
import os
import subprocess
import threading
import unittest
import uuid

from remote_exec import attempt as attempt_module
from remote_exec import transport

from support import RepoFixture


class AttemptTest(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write(".gitignore", "target/\nnode_modules/\n")
        self.write("tracked.txt", "one\n")
        self.write("other.txt", "two\n")
        self.write("gone.txt", "delete me\n")
        self.commit("base")
        self.executor = os.path.join(self.tmp, "executor")
        os.makedirs(self.executor, mode=0o700)
        self.transport = transport.LocalTransport()

    def new_attempt(self, attempt_id=None):
        return attempt_module.Attempt(
            self.transport, self.executor, "repo", "run", attempt_id or str(uuid.uuid4())
        )

    def stage(self, attempt):
        capture_dir = attempt_module.capture_to(self.repo)
        self.addCleanup(lambda: transport.cleanup(capture_dir))
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        attempt.prepare()
        self.transport.push_tree(capture_dir, attempt.staging)
        attempt.verify_input(captured["inputId"])
        return captured

    def publish(self, attempt, captured):
        attempt.publish(
            {
                "schemaVersion": 2,
                "attemptId": attempt.attempt_id,
                "inputId": captured["inputId"],
                "command": ["true"],
            }
        )

    def dispatch(self, argv, timeout=60, cwd=".", attempt_id=None, publish=True):
        attempt = self.new_attempt(attempt_id)
        captured = self.stage(attempt)
        if publish:
            self.publish(attempt, captured)
        result = attempt.dispatch(
            argv=argv,
            cwd=cwd,
            timeout_secs=timeout,
            env={"PATH": os.environ["PATH"]},
            input_id=captured["inputId"],
        )
        return attempt, captured, result

    def test_successful_command_and_selected_output(self):
        attempt, captured, result = self.dispatch(
            ["sh", "-c", "printf ok > added.txt; mkdir -p target; printf binary > target/build"]
        )
        self.assertEqual(result["phase"], "succeeded")
        self.assertEqual(result["inputId"], captured["inputId"])
        out = os.path.join(self.tmp, "collected")
        collected = attempt.collect(out)
        self.assertEqual(collected["phase"], "succeeded")
        self.assertTrue(os.path.exists(os.path.join(out, "source", "added.txt")))
        self.assertFalse(
            os.path.exists(os.path.join(out, "source", "target", "build")),
            "an ignored build tree is never collected",
        )
        self.assertFalse(os.path.exists(os.path.join(out, "artifacts")))

    def test_failed_command_is_a_terminal_result(self):
        _, _, result = self.dispatch(["sh", "-c", "echo bad >&2; exit 7"])
        self.assertEqual(result["phase"], "failed")
        self.assertEqual(result["exitCode"], 7)

    def test_cwd_escape_is_refused_before_execution(self):
        with self.assertRaises(attempt_module.UnknownOutcome):
            self.dispatch(["sh", "-c", "touch escaped"], cwd="../..")

    def test_attempt_directory_is_never_reused(self):
        attempt_id = str(uuid.uuid4())
        self.dispatch(["true"], attempt_id=attempt_id)
        with self.assertRaises(attempt_module.Blocked):
            self.stage(self.new_attempt(attempt_id))

    def test_concurrent_prepare_has_exactly_one_owner(self):
        attempt_id = str(uuid.uuid4())
        attempts = [self.new_attempt(attempt_id), self.new_attempt(attempt_id)]
        outcomes = []

        def prepare(attempt):
            try:
                attempt.prepare()
                outcomes.append("won")
            except attempt_module.Blocked:
                outcomes.append("lost")

        threads = [threading.Thread(target=prepare, args=(attempt,)) for attempt in attempts]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sorted(outcomes), ["lost", "won"])

    def test_interrupted_preparation_is_not_runnable(self):
        attempt = self.new_attempt()
        os.makedirs(attempt.path)
        with open(os.path.join(attempt.path, "state.json"), "w", encoding="utf-8") as handle:
            json.dump({"schemaVersion": 2, "phase": "preparing"}, handle)
        self.assertEqual(attempt.status()["phase"], "interrupted")
        with self.assertRaises(attempt_module.Blocked):
            attempt.prepare()

    def test_unverified_export_is_not_published(self):
        attempt = self.new_attempt()
        captured = self.stage(attempt)
        with open(os.path.join(attempt.staging, "work", "tracked.txt"), "w", encoding="utf-8") as handle:
            handle.write("tampered\n")
        with self.assertRaises(attempt_module.Blocked):
            attempt.verify_input(captured["inputId"])
        self.assertFalse(os.path.exists(os.path.join(attempt.path, "input.json")))

    def test_dispatch_is_claimed_once(self):
        attempt, captured, _ = self.dispatch(["true"])
        with self.assertRaises(attempt_module.Blocked):
            attempt.claim_dispatch(captured["inputId"])
        with self.assertRaises(attempt_module.Blocked):
            attempt.dispatch(
                argv=["sh", "-c", "echo again >> extra"],
                cwd=".",
                timeout_secs=10,
                env={"PATH": os.environ["PATH"]},
                input_id=captured["inputId"],
            )
        self.assertFalse(os.path.exists(os.path.join(attempt.path, "work", "extra")))

    def test_runner_refuses_a_second_execution(self):
        attempt, _, _ = self.dispatch(["true"])
        result_before = open(os.path.join(attempt.path, "result.json"), "rb").read()
        second = subprocess.run(
            ["python3", os.path.join(attempt.path, "runner.py"), os.path.join(attempt.path, "runner-config.json")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertNotEqual(second.returncode, 0)
        self.assertIn(b"terminal result already exists", second.stderr)
        self.assertEqual(result_before, open(os.path.join(attempt.path, "result.json"), "rb").read())

    def test_timeout_reports_cancelled_after_process_group_exit(self):
        _, _, result = self.dispatch(["sh", "-c", "sleep 30 & wait"], timeout=1)
        self.assertEqual(result["phase"], "cancelled")
        self.assertIn("confirmed terminated", result["reason"])

    def test_collect_excludes_ignored_build_trees_and_reports_new_source(self):
        attempt, captured, _ = self.dispatch(
            [
                "sh",
                "-c",
                "mkdir -p target node_modules src; printf bin > target/binary; "
                "printf dep > node_modules/dep; printf new > src/generated.rs; rm gone.txt",
            ]
        )
        out = os.path.join(self.tmp, "collected-selected")
        attempt.collect(out, with_delta=True)
        self.assertTrue(os.path.exists(os.path.join(out, "source", "src", "generated.rs")))
        self.assertFalse(os.path.exists(os.path.join(out, "source", "target")))
        self.assertFalse(os.path.exists(os.path.join(out, "source", "node_modules")))
        with open(os.path.join(out, "delta.json"), encoding="utf-8") as handle:
            delta = json.load(handle)
        changes = {entry["path"]: entry["change"] for entry in delta["changes"]}
        self.assertEqual(changes, {"src/generated.rs": "added", "gone.txt": "deleted"})
        self.assertEqual(delta["baseInputId"], captured["inputId"])

    def test_collect_verifies_log_hashes(self):
        attempt, _, _ = self.dispatch(["sh", "-c", "echo hello"])
        with open(os.path.join(attempt.path, "logs", "stdout.log"), "a", encoding="utf-8") as handle:
            handle.write("tampered\n")
        with self.assertRaises(attempt_module.Blocked):
            attempt.collect(os.path.join(self.tmp, "collected-logs"), with_logs=True)

    def test_artifacts_are_separately_requested(self):
        attempt, _, _ = self.dispatch(
            ["sh", "-c", 'mkdir -p "$REMOTE_EXEC_ARTIFACTS" && printf ok > "$REMOTE_EXEC_ARTIFACTS/x"']
        )
        out = os.path.join(self.tmp, "collected-artifacts")
        attempt.collect(out, with_artifacts=True)
        self.assertTrue(os.path.exists(os.path.join(out, "artifacts", "x")))

    def test_status_distinguishes_prepared_running_and_unknown(self):
        attempt = self.new_attempt()
        self.assertEqual(attempt.status()["phase"], "missing")
        captured = self.stage(attempt)
        self.assertEqual(attempt.status()["phase"], "interrupted")
        self.publish(attempt, captured)
        self.assertEqual(attempt.status()["phase"], "prepared")
        attempt.claim_dispatch(captured["inputId"])

        child = subprocess.Popen(["sleep", "30"])
        try:
            with open("/proc/sys/kernel/random/boot_id", encoding="utf-8") as handle:
                boot = handle.read().strip()
            with open(f"/proc/{child.pid}/stat", encoding="utf-8") as handle:
                start = handle.read().rsplit(")", 1)[1].split()[19]
            with open(os.path.join(attempt.path, "state.json"), "w", encoding="utf-8") as handle:
                json.dump({"phase": "running", "bootId": boot, "childPid": child.pid, "childStart": start}, handle)
            self.assertEqual(attempt.status()["phase"], "running")
        finally:
            child.terminate()
            child.wait(timeout=10)
        # The unit is gone without a result: unknown, not prepared.
        self.assertEqual(attempt.status()["phase"], "unknown")
