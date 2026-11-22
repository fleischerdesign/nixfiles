"""The built-in registry merge must preserve upstream entries and reject collisions."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


merge = load("merge", sys.argv.pop(1))


def write(path, value):
    path.write_text(json.dumps(value))


class Registry(unittest.TestCase):
    def test_empty_existing_is_replaced_with_declared_extensions(self):
        with tempfile.TemporaryDirectory() as directory:
            existing = Path(directory) / "registry.json"
            ours = Path(directory) / "ours.json"
            write(ours, {"version": 1, "extensions": [
                {"id": "openchamber-builtin-example", "directory": "example"},
            ]})
            merge.main(existing, ours)
            self.assertEqual(json.loads(existing.read_text())["extensions"], [
                {"id": "openchamber-builtin-example", "directory": "example"},
            ])

    def test_upstream_entries_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            existing = Path(directory) / "registry.json"
            ours = Path(directory) / "ours.json"
            write(existing, {"version": 1, "extensions": [
                {"id": "openchamber-builtin-upstream", "directory": "upstream"},
            ]})
            write(ours, {"version": 1, "extensions": [
                {"id": "openchamber-builtin-example", "directory": "example"},
            ]})
            merge.main(existing, ours)
            self.assertEqual(
                {item["id"] for item in json.loads(existing.read_text())["extensions"]},
                {"openchamber-builtin-upstream", "openchamber-builtin-example"},
            )

    def test_id_collision_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            existing = Path(directory) / "registry.json"
            ours = Path(directory) / "ours.json"
            write(existing, {"version": 1, "extensions": [
                {"id": "openchamber-builtin-example", "directory": "upstream"},
            ]})
            write(ours, {"version": 1, "extensions": [
                {"id": "openchamber-builtin-example", "directory": "example"},
            ]})
            with self.assertRaises(SystemExit):
                merge.main(existing, ours)


unittest.main()
