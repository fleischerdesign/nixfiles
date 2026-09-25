"""Exercise updater success and rollback without accessing upstream services."""

import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

UPDATER = Path(sys.argv.pop(1)).resolve()
SOURCE_HASH = "sha256-" + "B" * 43 + "="
CARGO_HASH = "sha256-" + "C" * 43 + "="

MOCK_NIX = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
manifest = json.loads(Path("packages/custom/example/manifest.json").read_text())
attribute = next(arg for arg in sys.argv if arg.startswith(".#example."))
attribute = attribute.removeprefix(".#example.").removesuffix(".drvPath")
drv = "/nix/store/test-" + attribute + ".drv"
if sys.argv[1] == "eval":
    print(drv, end="")
    sys.exit(0)
if os.environ.get("FAIL_BUILD") == "network":
    print("error: download failed: connection refused", file=sys.stderr)
    sys.exit(1)
key = "srcHash" if attribute == "src" else "cargoHash"
if not manifest[key]:
    # A dependency's hash mismatch must not be used for the requested output.
    if os.environ.get("FAIL_BUILD") == "dependency":
        drv = "/nix/store/unrelated.drv"
    actual = "sha256-" + ("B" if key == "srcHash" else "C") * 43 + "="
    print("error: hash mismatch in fixed-output derivation '" + drv + "':", file=sys.stderr)
    print("           likely URL: (unknown)", file=sys.stderr)
    print("            specified: sha256-" + "A" * 43 + "=", file=sys.stderr)
    print("                  got: " + actual, file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAIL_BUILD") == "verification":
    print("error: verification failed", file=sys.stderr)
    sys.exit(1)
'''


class SourceUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "features").mkdir()
        self.manifest = self.root / "packages/custom/example/manifest.json"
        self.manifest.parent.mkdir(parents=True)
        self.original = json.dumps({
            "name": "example", "version": "1.0.0", "srcHash": "original-source",
            "cargoHash": "original-cargo",
            "upstream": {"type": "github-source", "owner": "example", "repo": "example"},
        }) + "\n"
        self.manifest.write_text(self.original)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, contents in {
            "nix": MOCK_NIX,
            "curl": '#!/usr/bin/env bash\nprintf \'%s\\n\' \'{"tag_name":"v2.0.0"}\'\n',
        }.items():
            executable = self.bin / name
            contents = contents.replace("/usr/bin/env python3", sys.executable).replace("/usr/bin/env bash", shutil.which("bash"))
            executable.write_text(contents)
            executable.chmod(0o755)

    def run_update(self, failure=""):
        return subprocess.run(
            ["bash", str(UPDATER), "example"], cwd=self.root,
            env={**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "FAIL_BUILD": failure},
            text=True, capture_output=True, check=False,
        )

    def test_complete_update_verifies_both_hashes(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        actual = json.loads(self.manifest.read_text())
        self.assertEqual(actual["version"], "2.0.0")
        self.assertEqual(actual["srcHash"], SOURCE_HASH)
        self.assertEqual(actual["cargoHash"], CARGO_HASH)

    def test_failures_are_loud_and_restore_original_bytes(self):
        for failure in ("network", "dependency", "verification"):
            with self.subTest(failure=failure):
                result = self.run_update(failure)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("error:", result.stderr)
                self.assertEqual(self.manifest.read_text(), self.original)

    def test_missing_release_is_a_failure(self):
        (self.bin / "curl").write_text(f'#!{shutil.which("bash")}\necho "upstream unavailable" >&2\nexit 22\n')
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("upstream unavailable", result.stderr)
        self.assertEqual(self.manifest.read_text(), self.original)


if __name__ == "__main__":
    unittest.main()
