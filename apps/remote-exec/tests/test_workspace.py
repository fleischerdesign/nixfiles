import json
import os
import shutil
import subprocess
import time
import unittest
import uuid

from remote_exec import attempt as attempt_module
from remote_exec import source, transport, workspace as workspace_module

from support import RepoFixture


class WorkspaceFixture(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write(".gitignore", "target/\ngen/\n")
        self.write("tracked.txt", "one\n")
        self.write("other.txt", "two\n")
        self.write("gone.txt", "delete me\n")
        self.commit("base")
        self.executor = os.path.join(self.tmp, "executor")
        os.makedirs(self.executor, mode=0o700)
        self.transport = transport.LocalTransport()
        self._capture_dirs = []

    def tearDown(self):
        for path in self._capture_dirs:
            shutil.rmtree(path, ignore_errors=True)
        super().tearDown()

    def workspace(self, label="task", repo=None):
        return workspace_module.Workspace(
            self.transport,
            self.executor,
            "local",
            None,
            "repo",
            label,
            source.repo_identity(repo or self.repo),
        )

    def stage(self, attempt, repo=None):
        capture_dir = attempt_module.capture_to(repo or self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        attempt.prepare()
        self.transport.push_tree(capture_dir, attempt.staging)
        attempt.verify_input(captured["inputId"])
        attempt.workspace.sync(
            attempt.attempt_id,
            captured["inputId"],
            f"{attempt.staging}/input-files.json",
            f"{attempt.staging}/manifest.py",
        )
        return captured, capture_dir

    def publish(self, attempt, captured):
        attempt.publish(
            {
                "schemaVersion": 2,
                "attemptId": attempt.attempt_id,
                "inputId": captured["inputId"],
                "command": ["true"],
            }
        )

    def run_workspace(
        self,
        argv,
        label="task",
        run_id="run",
        repo=None,
        attempt_id=None,
        clean=False,
        timeout=60,
    ):
        ws = self.workspace(label, repo=repo)
        attempt = workspace_module.WorkspaceAttempt(
            self.transport, ws, attempt_id or str(uuid.uuid4())
        )
        attempt.clean = clean
        ws.prepare(attempt.attempt_id, None, clean=clean)
        capture_dir = attempt_module.capture_to(repo or self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, attempt.staging)
        attempt.verify_input(captured["inputId"])
        ws.sync(
            attempt.attempt_id,
            captured["inputId"],
            f"{attempt.staging}/input-files.json",
            f"{attempt.staging}/manifest.py",
        )
        self.publish(attempt, captured)
        result = attempt.dispatch(
            argv=argv,
            cwd=".",
            timeout_secs=timeout,
            env={"PATH": os.environ["PATH"]},
            input_id=captured["inputId"],
        )
        return attempt, captured, result


class WorkspaceIdentityTest(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write("a", "one\n")
        self.commit("base")
        self.other = os.path.join(self.tmp, "other")
        os.makedirs(self.other)

    def git_other(self, *args):
        return subprocess.run(
            ["git", "-C", self.other, *args],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout

    def test_same_label_different_repositories_never_collide(self):
        self.git_other("init", "-q")
        self.git_other("config", "user.name", "Test")
        self.git_other("config", "user.email", "test@example.invalid")
        with open(os.path.join(self.other, "b"), "w", encoding="utf-8") as handle:
            handle.write("two\n")
        self.git_other("add", "-A")
        self.git_other("-c", "commit.gpgsign=false", "commit", "-qm", "base")
        first = source.repo_identity(self.repo)
        second = source.repo_identity(self.other)
        self.assertNotEqual(first, second)
        a = workspace_module.workspace_key("/root", "host", "user", "repo", "task", first)
        b = workspace_module.workspace_key("/root", "host", "user", "repo", "task", second)
        self.assertNotEqual(a, b, "a label and repo id alone must not identify a repository")

    def test_key_binds_executor_identity_and_label(self):
        identity = source.repo_identity(self.repo)
        base = workspace_module.workspace_key("/root", "host", "user", "repo", "task", identity)
        self.assertEqual(
            base, workspace_module.workspace_key("/root", "host", "user", "repo", "task", identity)
        )
        self.assertNotEqual(
            base, workspace_module.workspace_key("/other", "host", "user", "repo", "task", identity)
        )
        self.assertNotEqual(
            base, workspace_module.workspace_key("/root", "other", "user", "repo", "task", identity)
        )
        self.assertNotEqual(
            base, workspace_module.workspace_key("/root", "host", "user", "repo", "other", identity)
        )


class WorkspaceReuseTest(WorkspaceFixture):
    def test_warm_repeat_preserves_output_home_and_mtime(self):
        attempt1, captured1, result1 = self.run_workspace(
            ["sh", "-c", 'echo built > out.txt; echo state > "$HOME/marker"; stat -c %Y tracked.txt']
        )
        self.assertEqual(result1["phase"], "succeeded")
        work = os.path.join(attempt1.workspace.path, "work")
        mtime_before = os.stat(os.path.join(work, "tracked.txt")).st_mtime_ns
        with open(os.path.join(work, "tracked.txt"), "rb") as handle:
            content_before = handle.read()

        attempt2, captured2, result2 = self.run_workspace(
            ["sh", "-c", 'echo again >> out.txt; cat "$HOME/marker"']
        )
        self.assertEqual(result2["phase"], "succeeded")
        self.assertEqual(captured1["inputId"], captured2["inputId"])
        self.assertEqual(result2["inputId"], captured2["inputId"])
        with open(os.path.join(work, "out.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "built\nagain\n")
        self.assertEqual(os.stat(os.path.join(work, "tracked.txt")).st_mtime_ns, mtime_before)
        with open(os.path.join(work, "tracked.txt"), "rb") as handle:
            self.assertEqual(handle.read(), content_before)
        with open(
            os.path.join(attempt2.path, "logs", "stdout.log"), encoding="utf-8"
        ) as handle:
            self.assertEqual(handle.read(), "state\n")

    def test_source_change_deletion_rename_mode_and_symlink(self):
        self.write("executable", "#!/bin/sh\n", mode=0o755)
        self.write("old/dir/file", "old\n")
        self.commit("more")
        attempt, _, _ = self.run_workspace(["true"])
        work = os.path.join(attempt.workspace.path, "work")

        os.unlink(os.path.join(self.repo, "gone.txt"))
        os.unlink(os.path.join(self.repo, "old/dir/file"))
        os.rmdir(os.path.join(self.repo, "old/dir"))
        os.rmdir(os.path.join(self.repo, "old"))
        self.write("new/renamed.txt", "renamed\n")
        self.write("tracked.txt", "changed\n")
        os.chmod(os.path.join(self.repo, "other.txt"), 0o755)
        os.symlink("tracked.txt", os.path.join(self.repo, "link.txt"))
        self.commit("changes")

        _, captured, result = self.run_workspace(["true"])
        self.assertEqual(result["phase"], "succeeded", result)
        with open(os.path.join(work, "tracked.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "changed\n")
        self.assertFalse(os.path.exists(os.path.join(work, "gone.txt")))
        self.assertFalse(os.path.exists(os.path.join(work, "old", "dir", "file")))
        with open(os.path.join(work, "new", "renamed.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "renamed\n")
        self.assertEqual(os.stat(os.path.join(work, "other.txt")).st_mode & 0o111, 0o111)
        self.assertEqual(os.readlink(os.path.join(work, "link.txt")), "tracked.txt")
        self.assertTrue(os.access(os.path.join(work, "executable"), os.X_OK))

    def test_ignored_outputs_and_untracked_sources(self):
        attempt, _, _ = self.run_workspace(
            ["sh", "-c", "mkdir -p target gen; echo bin > target/bin; echo keep > gen/out"]
        )
        work = os.path.join(attempt.workspace.path, "work")
        self.write("untracked.txt", "new\n")
        _, _, result = self.run_workspace(["true"])
        self.assertEqual(result["phase"], "succeeded")
        self.assertTrue(os.path.exists(os.path.join(work, "target", "bin")))
        self.assertTrue(os.path.exists(os.path.join(work, "gen", "out")))
        self.assertTrue(os.path.exists(os.path.join(work, "untracked.txt")))

    def test_same_label_in_another_repository_gets_another_workspace(self):
        first, _, _ = self.run_workspace(["sh", "-c", "echo first > marker.txt"])
        other = os.path.join(self.tmp, "other-repo")
        os.makedirs(other)
        env = dict(self.env)
        subprocess.run(["git", "-C", other, "init", "-q"], env=env, check=True)
        subprocess.run(
            ["git", "-C", other, "config", "user.name", "Test"], env=env, check=True
        )
        subprocess.run(
            ["git", "-C", other, "config", "user.email", "test@example.invalid"],
            env=env,
            check=True,
        )
        with open(os.path.join(other, "other.txt"), "w", encoding="utf-8") as handle:
            handle.write("other\n")
        subprocess.run(["git", "-C", other, "add", "-A"], env=env, check=True)
        subprocess.run(
            ["git", "-C", other, "-c", "commit.gpgsign=false", "commit", "-qm", "base"],
            env=env,
            check=True,
        )
        second, _, _ = self.run_workspace(
            ["sh", "-c", "echo second > marker.txt"], repo=other
        )
        self.assertNotEqual(first.workspace.path, second.workspace.path)
        with open(
            os.path.join(first.workspace.path, "work", "marker.txt"), encoding="utf-8"
        ) as handle:
            self.assertEqual(handle.read(), "first\n")
        with open(
            os.path.join(second.workspace.path, "work", "marker.txt"), encoding="utf-8"
        ) as handle:
            self.assertEqual(handle.read(), "second\n")

    def test_directory_and_file_type_changes(self):
        self.write("d/x", "x\n")
        self.write("e", "file\n")
        self.commit("shapes")
        attempt, _, _ = self.run_workspace(["true"])
        work = os.path.join(attempt.workspace.path, "work")

        os.unlink(os.path.join(self.repo, "d/x"))
        os.rmdir(os.path.join(self.repo, "d"))
        self.write("d", "file now\n")
        os.unlink(os.path.join(self.repo, "e"))
        self.write("e/y", "dir now\n")
        self.commit("shapes changed")
        _, _, result = self.run_workspace(["true"])
        self.assertEqual(result["phase"], "succeeded", result)
        self.assertTrue(os.path.isfile(os.path.join(work, "d")))
        self.assertTrue(os.path.isfile(os.path.join(work, "e", "y")))

    def test_remote_edit_of_managed_source_is_not_erased(self):
        attempt, _, _ = self.run_workspace(["true"])
        work = os.path.join(attempt.workspace.path, "work")
        with open(os.path.join(work, "tracked.txt"), "w", encoding="utf-8") as handle:
            handle.write("edited on the executor\n")
        self.write("tracked.txt", "changed on gateway\n")
        self.commit("gateway change")
        ws = self.workspace()
        second = workspace_module.WorkspaceAttempt(self.transport, ws, str(uuid.uuid4()))
        second.prepare()
        capture_dir = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, second.staging)
        with self.assertRaises(attempt_module.Blocked) as raised:
            ws.sync(
                second.attempt_id,
                captured["inputId"],
                f"{second.staging}/input-files.json",
                f"{second.staging}/manifest.py",
            )
        self.assertIn("changed outside remote-exec", str(raised.exception))
        with open(os.path.join(work, "tracked.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "edited on the executor\n")

    def test_new_source_colliding_with_retained_output_fails_closed(self):
        self.run_workspace(["sh", "-c", "mkdir -p gen; echo retained > gen/out"])
        self.write("gen", "now a source file\n")
        self.commit("gen file")
        ws = self.workspace()
        attempt = workspace_module.WorkspaceAttempt(self.transport, ws, str(uuid.uuid4()))
        attempt.prepare()
        capture_dir = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, attempt.staging)
        with self.assertRaises(attempt_module.Blocked) as raised:
            ws.sync(
                attempt.attempt_id,
                captured["inputId"],
                f"{attempt.staging}/input-files.json",
                f"{attempt.staging}/manifest.py",
            )
        self.assertIn("collides", str(raised.exception))
        attempt.publish_failed()


class WorkspaceLeaseTest(WorkspaceFixture):
    def test_second_attempt_is_refused_while_a_lease_is_active(self):
        first = workspace_module.WorkspaceAttempt(self.transport, self.workspace(), str(uuid.uuid4()))
        first.prepare()
        second = workspace_module.WorkspaceAttempt(self.transport, self.workspace(), str(uuid.uuid4()))
        with self.assertRaises(attempt_module.Blocked) as raised:
            second.prepare()
        self.assertIn("busy", str(raised.exception))
        # Disjoint workspace labels are independent.
        other = workspace_module.WorkspaceAttempt(
            self.transport, self.workspace("other"), str(uuid.uuid4())
        )
        other.prepare()
        self.assertTrue(os.path.isdir(other.workspace.path))

    def test_clean_resets_work_and_home(self):
        attempt1, _, _ = self.run_workspace(
            ["sh", "-c", 'echo cache > out.txt; echo state > "$HOME/state"']
        )
        work = os.path.join(attempt1.workspace.path, "work")
        home = os.path.join(attempt1.workspace.path, "home")
        self.assertTrue(os.path.exists(os.path.join(work, "out.txt")))
        self.assertTrue(os.path.exists(os.path.join(home, "state")))
        _, _, result = self.run_workspace(["true"], clean=True)
        self.assertEqual(result["phase"], "succeeded")
        self.assertFalse(os.path.exists(os.path.join(work, "out.txt")))
        self.assertFalse(os.path.exists(os.path.join(home, "state")))
        self.assertTrue(os.path.exists(os.path.join(work, "tracked.txt")))

    def test_incomplete_update_fails_closed_and_reset_recovers(self):
        ws = self.workspace()
        attempt = workspace_module.WorkspaceAttempt(self.transport, ws, str(uuid.uuid4()))
        attempt.prepare()
        capture_dir = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, attempt.staging)
        # Simulate a sync that died after starting to mutate the workspace.
        with open(
            os.path.join(ws.path, "state", "update-incomplete.json"), "w", encoding="utf-8"
        ) as handle:
            json.dump({"attemptId": attempt.attempt_id, "inputId": captured["inputId"]}, handle)
        contender = workspace_module.WorkspaceAttempt(self.transport, ws, str(uuid.uuid4()))
        with self.assertRaises(attempt_module.Blocked) as raised:
            contender.prepare()
        self.assertIn("updating", str(raised.exception))
        ws.reset()
        _, _, result = self.run_workspace(["true"])
        self.assertEqual(result["phase"], "succeeded")
        self.assertFalse(
            os.path.exists(os.path.join(ws.path, "state", "update-incomplete.json"))
        )

    def test_partial_sync_resumes_the_same_attempt(self):
        ws = self.workspace()
        attempt = workspace_module.WorkspaceAttempt(self.transport, ws, "resume-attempt")
        attempt.prepare()
        capture_dir = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, attempt.staging)
        ws.sync(
            attempt.attempt_id,
            captured["inputId"],
            f"{attempt.staging}/input-files.json",
            f"{attempt.staging}/manifest.py",
        )
        # Simulate a crash after a modified source was already installed.
        self.write("tracked.txt", "two\n")
        next_capture = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(next_capture)
        with open(os.path.join(next_capture, "input-files.json"), encoding="utf-8") as handle:
            next_input = json.load(handle)
        with open(os.path.join(ws.path, "work", "tracked.txt"), "w", encoding="utf-8") as handle:
            handle.write("two\n")
        with open(
            os.path.join(ws.path, "state", "update-incomplete.json"), "w", encoding="utf-8"
        ) as handle:
            json.dump({"attemptId": "resume-attempt", "inputId": next_input["inputId"]}, handle)
        _, _, result = self.run_workspace(["true"], attempt_id="resume-attempt")
        self.assertEqual(result["phase"], "succeeded", result)
        with open(
            os.path.join(ws.path, "work", "tracked.txt"), encoding="utf-8"
        ) as handle:
            self.assertEqual(handle.read(), "two\n")

    def test_unknown_lease_needs_explicit_force(self):
        ws = self.workspace()
        attempt = workspace_module.WorkspaceAttempt(self.transport, ws, str(uuid.uuid4()))
        attempt.prepare()
        lease_path = os.path.join(ws.path, "state", "lease.json")
        with open(lease_path, "r", encoding="utf-8") as handle:
            lease = json.load(handle)
        lease.update({"phase": "running", "attemptId": attempt.attempt_id})
        with open(lease_path, "w", encoding="utf-8") as handle:
            json.dump(lease, handle)
        with self.assertRaises(attempt_module.Blocked):
            ws.reset()
        value = ws.reset(force=True)
        self.assertTrue(value["reset"])

    def test_timeout_ends_in_a_terminal_cancelled_lease(self):
        _, _, result = self.run_workspace(["sh", "-c", "sleep 30 & wait"], timeout=1)
        self.assertEqual(result["phase"], "cancelled")
        with open(
            os.path.join(self.workspace().path, "state", "lease.json"), encoding="utf-8"
        ) as handle:
            lease = json.load(handle)
        self.assertEqual(lease["phase"], "terminal")
        self.assertEqual(lease["resultPhase"], "cancelled")

    def test_prune_is_dry_run_by_default_and_skips_active_lease(self):
        attempt1, _, _ = self.run_workspace(["true"])
        ws = attempt1.workspace
        live = workspace_module.WorkspaceAttempt(self.transport, ws, str(uuid.uuid4()))
        live.prepare()
        report = ws.prune(apply=True, keep=0, max_age_days=0)
        self.assertIn("not terminal", json.dumps(report))
        self.assertTrue(os.path.isdir(attempt1.path))

    def test_prune_dry_run_then_apply_and_idempotent(self):
        attempt1, _, _ = self.run_workspace(["true"], attempt_id="old-attempt")
        report = attempt1.workspace.prune(apply=False, keep=0, max_age_days=0)
        removed = [item for item in report["removed"] if item.get("attemptId") == "old-attempt"]
        self.assertEqual(len(removed), 1)
        self.assertTrue(removed[0]["dryRun"])
        self.assertTrue(os.path.isdir(attempt1.path))
        applied = attempt1.workspace.prune(apply=True, keep=0, max_age_days=0)
        self.assertTrue(any(item.get("attemptId") == "old-attempt" for item in applied["removed"]))
        self.assertFalse(os.path.exists(attempt1.path))
        again = attempt1.workspace.prune(apply=True, keep=0, max_age_days=0)
        self.assertEqual(again["removed"], [])


class WorkspaceCollectTest(WorkspaceFixture):
    def test_old_attempt_collects_its_immutable_snapshot(self):
        attempt1, captured1, _ = self.run_workspace(
            ["sh", "-c", "printf first > generated.txt"]
        )
        self.write("tracked.txt", "second\n")
        self.commit("second")
        _, captured2, _ = self.run_workspace(
            ["sh", "-c", "printf second > generated.txt"], attempt_id="second-attempt"
        )
        self.assertNotEqual(captured1["inputId"], captured2["inputId"])
        out = os.path.join(self.tmp, "collected-old")
        result = attempt1.collect(out, with_delta=True)
        self.assertEqual(result["phase"], "succeeded")
        with open(os.path.join(out, "source", "generated.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "first")
        with open(os.path.join(out, "source", "tracked.txt"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "one\n")
        with open(os.path.join(out, "delta.json"), encoding="utf-8") as handle:
            delta = json.load(handle)
        self.assertEqual(
            {entry["path"] for entry in delta["changes"]}, {"generated.txt"}
        )

    def test_snapshot_failure_refuses_source_collection(self):
        attempt = workspace_module.WorkspaceAttempt(
            self.transport, self.workspace(), str(uuid.uuid4())
        )
        attempt.prepare()
        capture_dir = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, attempt.staging)
        attempt.verify_input(captured["inputId"])
        attempt.workspace.sync(
            attempt.attempt_id,
            captured["inputId"],
            f"{attempt.staging}/input-files.json",
            f"{attempt.staging}/manifest.py",
        )
        self.publish(attempt, captured)
        # A finalize failure is a terminal diagnostic, not a rerun: dispatch
        # without a finalizer so the runner records a snapshot failure.
        attempt.dispatch_files = lambda: {}
        result = attempt.dispatch(
            ["true"], ".", 30, {"PATH": os.environ["PATH"]}, captured["inputId"]
        )
        self.assertEqual(result["phase"], "succeeded")
        self.assertEqual(result["output"]["status"], "failed")
        with self.assertRaises(attempt_module.Blocked) as raised:
            attempt.collect(os.path.join(self.tmp, "no-snapshot"))
        self.assertIn("no immutable source snapshot", str(raised.exception))

    def test_fresh_attempt_is_not_a_workspace(self):
        fresh = attempt_module.Attempt(
            self.transport, self.executor, "repo", "run", str(uuid.uuid4())
        )
        self.assertFalse(fresh.path.startswith(os.path.join(self.executor, "workspaces")))
        fresh.prepare()
        capture_dir = attempt_module.capture_to(self.repo)
        self._capture_dirs.append(capture_dir)
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        self.transport.push_tree(capture_dir, fresh.staging)
        fresh.verify_input(captured["inputId"])
        fresh.publish(
            {"schemaVersion": 2, "attemptId": fresh.attempt_id, "inputId": captured["inputId"]}
        )
        result = fresh.dispatch(
            ["true"], ".", 30, {"PATH": os.environ["PATH"]}, captured["inputId"]
        )
        self.assertEqual(result["phase"], "succeeded")
