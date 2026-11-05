import hashlib
import json
import os
import shutil
import tempfile
import unittest

from remote_exec import manifest


class InputIdTest(unittest.TestCase):
    def test_digest_covers_path_mode_and_content(self):
        first = [{"path": "a", "type": "file", "mode": "100644", "size": 1, "sha256": "x"}]
        same = [dict(first[0])]
        other_mode = [dict(first[0], mode="100755")]
        other_path = [dict(first[0], path="b")]
        self.assertEqual(manifest.input_id(first), manifest.input_id(same))
        self.assertNotEqual(manifest.input_id(first), manifest.input_id(other_mode))
        self.assertNotEqual(manifest.input_id(first), manifest.input_id(other_path))

    def test_traversal_and_dot_git_are_refused(self):
        for value in ("../x", "/etc/passwd", "a//b", "a/./b", ".git/config", "a/.git/HEAD"):
            with self.assertRaises(manifest.ManifestError, msg=value):
                manifest.validate_relpath(value)

    def test_symlinks_must_stay_inside(self):
        manifest.validate_symlink("dir/link", "../target")
        manifest.validate_symlink("link", "target")
        for rel, target in (
            ("link", "/etc/passwd"),
            ("dir/link", "../../outside"),
            ("link", "../outside"),
        ):
            with self.assertRaises(manifest.ManifestError, msg=(rel, target)):
                manifest.validate_symlink(rel, target)


class VerifyTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="remote-exec-verify-")
        self.work = os.path.join(self.root, "work")
        self.path = os.path.join(self.root, "manifest.json")
        os.makedirs(self.work)
        with open(os.path.join(self.work, "a.txt"), "w", encoding="utf-8") as handle:
            handle.write("one\n")
        self.value = manifest.build_manifest(self.work, "abc")
        manifest.write_manifest(self.value, self.path)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_matching_tree_verifies(self):
        self.assertEqual(
            manifest.verify(self.work, self.path, self.value["inputId"]), self.value["inputId"]
        )

    def test_changed_content_fails(self):
        with open(os.path.join(self.work, "a.txt"), "w", encoding="utf-8") as handle:
            handle.write("two\n")
        with self.assertRaises(manifest.ManifestError):
            manifest.verify(self.work, self.path)

    def test_extra_file_fails(self):
        with open(os.path.join(self.work, "extra"), "w", encoding="utf-8") as handle:
            handle.write("x")
        with self.assertRaises(manifest.ManifestError):
            manifest.verify(self.work, self.path)

    def test_mode_change_fails(self):
        os.chmod(os.path.join(self.work, "a.txt"), 0o755)
        with self.assertRaises(manifest.ManifestError):
            manifest.verify(self.work, self.path)

    def test_wrong_expected_id_fails(self):
        with self.assertRaises(manifest.ManifestError):
            manifest.verify(self.work, self.path, "0" * 64)

    def test_git_directory_fails(self):
        os.makedirs(os.path.join(self.work, ".git"))
        with self.assertRaises(manifest.ManifestError):
            manifest.verify(self.work, self.path)

    def test_manifest_with_wrong_digest_fails(self):
        with open(self.path, "r", encoding="utf-8") as handle:
            value = json.load(handle)
        value["inputId"] = hashlib.sha256(b"not it").hexdigest()
        with open(self.path, "w", encoding="utf-8") as handle:
            json.dump(value, handle)
        with self.assertRaises(manifest.ManifestError):
            manifest.load_manifest(self.path)

    def test_manifest_entry_cannot_name_an_unsafe_path(self):
        value = dict(self.value)
        value["files"] = [dict(self.value["files"][0], path="../escape")]
        value["inputId"] = manifest.input_id(value["files"])
        with open(self.path, "w", encoding="utf-8") as handle:
            json.dump(value, handle)
        with self.assertRaises(manifest.ManifestError):
            manifest.load_manifest(self.path)


class SelectionTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="remote-exec-selection-")
        os.makedirs(os.path.join(self.root, "src"))
        with open(os.path.join(self.root, "src", "a.rs"), "w", encoding="utf-8") as handle:
            handle.write("fn a() {}\n")
        with open(os.path.join(self.root, "target.bin"), "w", encoding="utf-8") as handle:
            handle.write("build product\n")
        self.value = manifest.build_selection(self.root, ["src/a.rs"])
        self.path = os.path.join(self.root, "output.json")
        manifest.write_manifest(self.value, self.path)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_selection_ignores_unselected_build_products(self):
        self.assertEqual(
            manifest.verify_selection(self.root, self.path, self.value["inputId"]),
            self.value["inputId"],
        )

    def test_selection_detects_a_changed_selected_file(self):
        with open(os.path.join(self.root, "src", "a.rs"), "w", encoding="utf-8") as handle:
            handle.write("fn b() {}\n")
        with self.assertRaises(manifest.ManifestError):
            manifest.verify_selection(self.root, self.path)

    def test_selection_refuses_a_missing_selected_file(self):
        os.unlink(os.path.join(self.root, "src", "a.rs"))
        with self.assertRaises(manifest.ManifestError):
            manifest.verify_selection(self.root, self.path)
