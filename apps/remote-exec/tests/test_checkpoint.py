import os
import shutil
import subprocess
import tempfile
import unittest

from remote_exec import checkpoint, manifest, source

from support import RepoFixture


class CheckpointTest(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write(".gitignore", "ignored/\n")
        self.write("tracked.txt", "base\n")
        self.write("deleted.txt", "gone\n")
        self.write("exec.sh", "#!/bin/sh\necho ok\n", mode=0o755)
        self.write("ignored/secret.txt", "no\n")
        os.symlink("tracked.txt", os.path.join(self.repo, "link"))
        self.write("line\nbreak.txt", "newline name\n")
        self.write("üñïçødé.txt", "unicode name\n")
        self.write("-dash.txt", "dash name\n")
        self.commit("base")

        self.write("tracked.txt", "base\ndirty\n")
        self.write("untracked.txt", "new\n")
        os.unlink(os.path.join(self.repo, "deleted.txt"))
        self.write("staged.txt", "staged\n")
        self.git("add", "staged.txt")

        self.capture_dir = tempfile.mkdtemp(prefix="remote-exec-checkpoint-")
        self.addCleanup(lambda: shutil.rmtree(self.capture_dir, ignore_errors=True))
        self.captured = source.capture(self.repo, self.capture_dir)

    def test_checkpoint_preserves_parent_and_round_trips_through_a_worktree(self):
        head = self.git("rev-parse", "HEAD")
        index_path = os.path.join(self.repo, ".git", "index")
        with open(index_path, "rb") as handle:
            index = handle.read()
        with open(os.path.join(self.repo, "tracked.txt"), "rb") as handle:
            tracked = handle.read()

        receipt = checkpoint.create(self.repo, self.capture_dir)

        self.assertEqual(head, self.git("rev-parse", "HEAD"))
        with open(index_path, "rb") as handle:
            self.assertEqual(index, handle.read())
        with open(os.path.join(self.repo, "tracked.txt"), "rb") as handle:
            self.assertEqual(tracked, handle.read())
        self.assertEqual(receipt["inputId"], self.captured["inputId"])
        self.assertEqual(receipt["parentRevision"], head.decode().strip())
        commit = receipt["checkpoint"]["commit"]
        ref = receipt["checkpoint"]["ref"]
        self.assertEqual(self.git("rev-parse", ref).decode().strip(), commit)

        worktree = os.path.join(self.tmp, "checkout")
        self.git("worktree", "add", "--detach", worktree, commit)
        try:
            checkout_capture = tempfile.mkdtemp(prefix="remote-exec-checkout-")
            try:
                value = source.capture(worktree, checkout_capture)
                self.assertEqual(value["inputId"], self.captured["inputId"])
                self.assertNotEqual(value["baseRevision"], self.captured["baseRevision"])
                self.assertTrue(os.path.islink(os.path.join(checkout_capture, "work", "link")))
                self.assertTrue(os.path.exists(os.path.join(checkout_capture, "work", "line\nbreak.txt")))
                self.assertTrue(os.path.exists(os.path.join(checkout_capture, "work", "üñïçødé.txt")))
                self.assertTrue(os.path.exists(os.path.join(checkout_capture, "work", "-dash.txt")))
            finally:
                shutil.rmtree(checkout_capture, ignore_errors=True)
        finally:
            self.git("worktree", "remove", "--force", worktree)

    def test_checkpoint_is_idempotent_and_rejects_a_different_input(self):
        first = checkpoint.create(self.repo, self.capture_dir, "consumer-a")
        again = checkpoint.create(self.repo, self.capture_dir, "consumer-a")
        self.assertTrue(again["replayed"])
        self.assertEqual(again["checkpoint"]["commit"], first["checkpoint"]["commit"])

        self.write("tracked.txt", "base\ndirty\nmore\n")
        changed = tempfile.mkdtemp(prefix="remote-exec-checkpoint-")
        self.addCleanup(lambda: shutil.rmtree(changed, ignore_errors=True))
        value = source.capture(self.repo, changed)
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.create(self.repo, changed, first["checkpoint"]["id"])
        self.assertNotEqual(value["inputId"], first["inputId"])

    def test_default_callers_get_independent_pins(self):
        first = checkpoint.create(self.repo, self.capture_dir)
        second = checkpoint.create(self.repo, self.capture_dir)
        self.assertNotEqual(first["checkpoint"]["ref"], second["checkpoint"]["ref"])
        self.assertEqual(first["inputId"], second["inputId"])
        self.assertEqual(first["checkpoint"]["tree"], second["checkpoint"]["tree"])

        checkpoint.release(self.repo, first["checkpoint"]["ref"], first["checkpoint"]["commit"])
        self.assertEqual(
            self.git("rev-parse", second["checkpoint"]["ref"]).decode().strip(),
            second["checkpoint"]["commit"],
            "releasing one consumer's pin must not remove another",
        )
        checkpoint.release(self.repo, second["checkpoint"]["ref"], second["checkpoint"]["commit"])

    def test_same_content_after_a_new_parent_is_rejected_for_an_explicit_id(self):
        first = checkpoint.create(self.repo, self.capture_dir, "consumer-a")
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "later")
        later = tempfile.mkdtemp(prefix="remote-exec-later-")
        self.addCleanup(lambda: shutil.rmtree(later, ignore_errors=True))
        value = source.capture(self.repo, later)
        self.assertEqual(value["inputId"], first["inputId"])
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.create(self.repo, later, "consumer-a")

    def test_a_forged_input_trailer_on_the_wrong_tree_is_rejected(self):
        receipt = checkpoint.create(self.repo, self.capture_dir, "consumer-a")
        empty_tree = subprocess.run(
            ["git", "-C", self.repo, "hash-object", "-t", "tree", "--stdin"],
            input=b"",
            stdout=subprocess.PIPE,
            env=self.env,
            check=True,
        ).stdout.decode().strip()
        forged_message = (
            "forged\n\nRemote-Exec-Input-Id: " + receipt["inputId"] + "\n"
        )
        forged = subprocess.run(
            ["git", "-C", self.repo, "commit-tree", empty_tree, "-F", "-"],
            input=forged_message.encode(),
            stdout=subprocess.PIPE,
            env=self.env,
            check=True,
        ).stdout.decode().strip()
        self.git("update-ref", receipt["checkpoint"]["ref"], forged)
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.create(self.repo, self.capture_dir, "consumer-a")

    def test_reference_transaction_hook_is_not_executed(self):
        marker = os.path.join(self.tmp, "hook-ran")
        hook = os.path.join(self.repo, ".git", "hooks", "reference-transaction")
        os.makedirs(os.path.dirname(hook), exist_ok=True)
        with open(hook, "w", encoding="utf-8") as handle:
            handle.write(f"#!/bin/sh\ntouch {marker}\n")
        os.chmod(hook, 0o755)
        receipt = checkpoint.create(self.repo, self.capture_dir, "consumer-a")
        checkpoint.release(self.repo, receipt["checkpoint"]["ref"], receipt["checkpoint"]["commit"])
        self.assertFalse(os.path.exists(marker), "checkpoint Git mutations must disable hooks")

    def test_release_requires_the_expected_commit_and_owned_namespace(self):
        receipt = checkpoint.create(self.repo, self.capture_dir)
        ref = receipt["checkpoint"]["ref"]
        commit = receipt["checkpoint"]["commit"]
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.release(self.repo, ref, "0" * 40)
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.release(self.repo, "refs/heads/main", commit)
        released = checkpoint.release(self.repo, ref, commit)
        self.assertTrue(released["released"])
        again = checkpoint.release(self.repo, ref, commit)
        self.assertFalse(again["released"])
        self.assertEqual(again["reason"], "already absent")

    def test_clean_filters_are_not_executed_and_content_is_not_converted(self):
        marker = os.path.join(self.tmp, "filter-ran")
        self.git("config", "filter.evil.clean", f"sh -c 'touch {marker}; cat'")
        self.git("config", "filter.evil.smudge", "cat")
        self.write(".gitattributes", "*.txt filter=evil\n")
        self.write("filtered.txt", "raw bytes\n")
        capture_dir = tempfile.mkdtemp(prefix="remote-exec-filter-")
        self.addCleanup(lambda: shutil.rmtree(capture_dir, ignore_errors=True))
        capture = source.capture(self.repo, capture_dir)
        receipt = checkpoint.create(self.repo, capture_dir)
        blob = self.git("rev-parse", f"{receipt['checkpoint']['commit']}:filtered.txt").decode().strip()
        content = self.git("cat-file", "blob", blob)
        self.assertEqual(content, b"raw bytes\n")
        self.assertFalse(os.path.exists(marker), "the clean filter must never run for a checkpoint")

    def test_verify_source_detects_a_different_tree(self):
        with self.assertRaises(manifest.ManifestError):
            manifest.verify(
                os.path.join(self.capture_dir, "work"),
                os.path.join(self.capture_dir, "input-files.json"),
                "0" * 64,
            )
