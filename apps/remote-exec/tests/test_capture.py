import json
import os
import stat
import unittest

from remote_exec import source

from support import RepoFixture


class CaptureTest(RepoFixture):
    def setUp(self):
        super().setUp()
        self.write(
            ".gitignore",
            "ignored/\n*.log\ntracked-but-ignored.txt\n",
        )
        self.write("nested/.gitignore", "*.tmp\n!keep.tmp\n")
        self.write("tracked.txt", "committed\n")
        self.write("deleted.txt", "gone soon\n")
        self.write("tracked-but-ignored.txt", "tracked wins\n")
        self.git("add", "-f", "tracked-but-ignored.txt")
        self.write("script.sh", "#!/bin/sh\necho ok\n", mode=0o755)
        self.write("nested/a.tmp", "drop me\n")
        self.write("nested/keep.tmp", "keep me\n")
        os.symlink("tracked.txt", os.path.join(self.repo, "link"))
        self.write("a b.txt", "space in the name\n")
        self.commit("base")

        # dirty, staged and untracked input
        self.write("tracked.txt", "committed\ndirty\n")
        self.write("staged.txt", "staged\n")
        self.git("add", "staged.txt")
        self.write("untracked.txt", "new\n")
        os.unlink(os.path.join(self.repo, "deleted.txt"))
        self.write("ignored/generated.log", "not source\n")
        self.write("nested/b.tmp", "drop me too\n")

    def capture(self, name="capture", extra=()):
        out = self.out(name)
        value = source.capture(self.repo, out, tuple(extra))
        return out, value

    def entries(self, value):
        return {entry["path"]: entry for entry in value["files"]}

    def test_working_tree_is_exported_without_mutating_the_repository(self):
        head = self.git("rev-parse", "HEAD")
        index_path = os.path.join(self.repo, ".git", "index")
        with open(index_path, "rb") as handle:
            index = handle.read()

        out, value = self.capture()

        self.assertEqual(head, self.git("rev-parse", "HEAD"))
        with open(index_path, "rb") as handle:
            self.assertEqual(index, handle.read())
        self.assertEqual(
            self.git("status", "--porcelain").decode().count("\n"),
            4,
            "capture must not stage, commit or delete the caller's changes",
        )

        entries = self.entries(value)
        self.assertEqual(entries["tracked.txt"]["size"], len("committed\ndirty\n"))
        self.assertIn("staged.txt", entries)
        self.assertIn("untracked.txt", entries)
        self.assertIn("tracked-but-ignored.txt", entries, "tracked bytes are source even when ignored")
        self.assertNotIn("deleted.txt", entries)
        self.assertNotIn("ignored/generated.log", entries)
        self.assertNotIn("nested/a.tmp", entries)
        self.assertIn("nested/keep.tmp", entries, "a nested negation is a project rule")
        self.assertNotIn("nested/b.tmp", entries)
        self.assertEqual(entries["script.sh"]["mode"], "100755")
        self.assertEqual(entries["link"]["type"], "symlink")
        self.assertEqual(entries["link"]["target"], "tracked.txt")
        self.assertIn("a b.txt", entries)

        work = os.path.join(out, "work")
        self.assertFalse(os.path.exists(os.path.join(work, ".git")))
        self.assertFalse(os.path.exists(os.path.join(work, "deleted.txt")))
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(work, "script.sh")).st_mode), 0o755)
        self.assertTrue(os.path.islink(os.path.join(work, "link")))

    def test_manifest_matches_the_exported_tree(self):
        from remote_exec import manifest

        out, value = self.capture()
        self.assertEqual(
            manifest.verify(os.path.join(out, "work"), os.path.join(out, "input-files.json")),
            value["inputId"],
        )

    def test_global_gitignore_does_not_change_the_input(self):
        global_ignore = os.path.join(self.home, ".config", "git", "ignore")
        os.makedirs(os.path.dirname(global_ignore), exist_ok=True)
        with open(global_ignore, "w", encoding="utf-8") as handle:
            handle.write("untracked.txt\n")
        out, value = self.capture()
        self.assertIn("untracked.txt", self.entries(value))

    def test_explicit_extra_path_is_included_and_must_exist(self):
        out, value = self.capture("capture-extra", extra=("ignored/generated.log",))
        self.assertIn("ignored/generated.log", self.entries(value))
        with self.assertRaises(source.SourceError):
            self.capture("capture-missing", extra=("does-not-exist",))

    def test_capture_target_must_be_empty(self):
        out = self.out("occupied")
        os.makedirs(out)
        with open(os.path.join(out, "file"), "w", encoding="utf-8") as handle:
            handle.write("x")
        with self.assertRaises(source.SourceError):
            source.capture(self.repo, out)

    def test_escaping_symlink_fails_closed(self):
        os.symlink("../../outside", os.path.join(self.repo, "escape"))
        with self.assertRaises(source.SourceError):
            self.capture("capture-escape")

    def test_absolute_symlink_fails_closed(self):
        os.symlink("/etc/passwd", os.path.join(self.repo, "absolute"))
        with self.assertRaises(source.SourceError):
            self.capture("capture-absolute")

    def test_gitlink_is_refused_instead_of_exported_partially(self):
        self.git("update-index", "--add", "--cacheinfo", "160000,1111111111111111111111111111111111111111,sub")
        with self.assertRaises(source.SourceError) as raised:
            self.capture("capture-submodule")
        self.assertIn("submodule", str(raised.exception))

    def test_lfs_attributes_are_refused(self):
        self.write(".gitattributes", "*.bin filter=lfs diff=lfs merge=lfs -text\n")
        self.git("add", ".gitattributes")
        with self.assertRaises(source.SourceError) as raised:
            self.capture("capture-lfs")
        self.assertIn("LFS", str(raised.exception))

    def test_capture_reports_the_base_revision(self):
        out, value = self.capture()
        self.assertEqual(value["baseRevision"], self.git("rev-parse", "HEAD").decode().strip())
        with open(os.path.join(out, "input-files.json"), encoding="utf-8") as handle:
            stored = json.load(handle)
        self.assertEqual(stored["inputId"], value["inputId"])

    def test_a_file_changing_during_capture_fails_closed(self):
        def mutate(rel):
            if rel == "tracked.txt":
                with open(os.path.join(self.repo, rel), "a", encoding="utf-8") as handle:
                    handle.write("changed while reading\n")

        with self.assertRaises(source.SourceError) as raised:
            source.capture(self.repo, self.out("capture-race"), _after_read=mutate)
        self.assertIn("changed while it was captured", str(raised.exception))

    def test_an_index_change_during_capture_fails_closed(self):
        def stage(_rel):
            self.git("add", "-A")

        with self.assertRaises(source.SourceError) as raised:
            source.capture(self.repo, self.out("capture-index"), _after_copy=stage)
        self.assertIn("index changed", str(raised.exception))
