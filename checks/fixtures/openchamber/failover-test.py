"""The failover patch must add provider.go-limit to both boundaries and fail loudly when the shape drifts."""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


patch = load("patch", sys.argv.pop(1))
fixtures = Path(sys.argv.pop(1))


class FailoverPatch(unittest.TestCase):
    def test_patch_adds_go_limit_to_both_boundaries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in (
                "packages/web/server/lib/limit-failover/policy.ts",
                "packages/web/server/lib/limit-failover/runtime.ts",
            ):
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(fixtures / Path(relative).name, destination)
            patch.main(root)
            for relative in (
                "packages/web/server/lib/limit-failover/policy.ts",
                "packages/web/server/lib/limit-failover/runtime.ts",
            ):
                self.assertIn("provider.go-limit", (root / relative).read_text())
            # A second run is a no-op, so an upstream fix does not need a new patch shape.
            patch.main(root)

    def test_changed_shape_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy = root / "packages/web/server/lib/limit-failover/policy.ts"
            runtime = root / "packages/web/server/lib/limit-failover/runtime.ts"
            policy.parent.mkdir(parents=True, exist_ok=True)
            policy.write_text("const LIMIT_ERROR_TYPES = new Set(['provider.quota'])\n")
            runtime.write_text("const LIMIT_ERROR_TYPES = new Set(['provider.quota'])\n")
            with self.assertRaises(SystemExit):
                patch.main(root)


unittest.main()
