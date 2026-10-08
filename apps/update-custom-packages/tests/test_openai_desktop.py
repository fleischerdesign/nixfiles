"""Check release resolution and reject ambiguous or executable metadata."""

import importlib.util
import sys
import unittest

spec = importlib.util.spec_from_file_location("metadata", sys.argv.pop())
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def test_immutable_artifact(self):
        result = metadata.release_metadata("versions=(26.1002.52244 26.930.61225)\n", "x86_64")
        self.assertEqual(result["version"], "26.1002.52244")
        self.assertTrue(result["url"].endswith("/26.1002.52244/x86_64/chatgpt-bin-26.1002.52244-1-x86_64.pkg.tar.zst"))

    def test_reject_untrusted_or_ambiguous_release_list(self):
        for installer in ["", "versions=()", "versions=($(id))", "versions=(26.1.2)\nversions=(26.3.4)"]:
            with self.subTest(installer=installer), self.assertRaises(ValueError):
                metadata.release_metadata(installer, "x86_64")

    def test_reject_unknown_architecture(self):
        with self.assertRaises(ValueError):
            metadata.release_metadata("versions=(26.1.2)", "unknown")


if __name__ == "__main__":
    unittest.main()
