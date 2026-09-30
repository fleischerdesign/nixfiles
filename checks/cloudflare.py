"""Verify nod activation and Cloudflare reconciliation without credentials or network I/O."""

from contextlib import redirect_stdout
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


source, fixture, published = sys.argv[1:]
module_spec = importlib.util.spec_from_file_location("cloudflare_sync", source)
sync = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(sync)


def record(name, content, comment="Service fixture", kind="A"):
    return {
        "name": name,
        "type": kind,
        "content": content,
        "proxied": False,
        "ttl": 1,
        "comment": comment,
    }


class FakeCloudflare:
    def __init__(self):
        self.calls = []
        self.settings = {"ssl": "flexible", "always_use_https": "off", "min_tls_version": "1.0"}
        self.records = [
            record("update.example.test", "192.0.2.1"),
            record("unchanged.example.test", "192.0.2.2"),
            record("stale.example.test", "192.0.2.3"),
            record("manual.example.test", "192.0.2.4", "Operator-owned"),
            record("_acme-challenge.example.test", "validation", None, "TXT"),
            record("outside.other.test", "192.0.2.5"),
        ]
        for index, item in enumerate(self.records):
            item["id"] = str(index)

    def request(self, token, endpoint, method="GET", data=None):
        assert token == "isolated-test-token"
        self.calls.append((method, endpoint, copy.deepcopy(data)))
        if endpoint == "/zones?name=example.test":
            return {"result": [{"id": "zone"}]}
        if "/settings/" in endpoint:
            setting = endpoint.rsplit("/", 1)[1]
            if method == "PATCH":
                self.settings[setting] = data["value"]
            return {"result": {"value": self.settings[setting]}}
        if endpoint == "/zones/zone/dns_records?per_page=100":
            return {"result": copy.deepcopy(self.records)}
        if method == "POST":
            assert not any(
                item["name"] == data["name"] and "CNAME" in (item["type"], data["type"])
                for item in self.records
            ), "a stale CNAME must be removed before its replacement is created"
            self.records.append(data | {"id": "created-" + data["name"]})
        elif method == "PUT":
            record_id = endpoint.rsplit("/", 1)[1]
            item = next(item for item in self.records if item["id"] == record_id)
            item.update(data)
        elif method == "DELETE":
            record_id = endpoint.rsplit("/", 1)[1]
            self.records = [item for item in self.records if item["id"] != record_id]
        else:
            raise AssertionError(f"Unexpected API request: {method} {endpoint}")
        return {"result": {}, "success": True}

    def writes(self):
        return [call for call in self.calls if call[0] != "GET"]


class CloudflareTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.api = FakeCloudflare()
        self.spec = {
            "domain": "example.test",
            "settings": {"ssl": "strict", "always_use_https": "on", "min_tls_version": "1.3"},
            "records": [
                record("create.example.test", "192.0.2.10"),
                record("update.example.test", "192.0.2.11"),
                record("unchanged.example.test", "192.0.2.2"),
            ],
        }

    def reconcile(self, *options, api=None):
        spec_file = self.root / "spec.json"
        spec_file.write_text(json.dumps(self.spec))
        output = io.StringIO()
        with (
            patch.object(sys, "argv", [source, "--spec", str(spec_file), *options]),
            patch.object(sync, "get_token", return_value="isolated-test-token"),
            patch.object(sync, "api_request", side_effect=api or self.api.request),
            redirect_stdout(output),
        ):
            sync.main()
        return output.getvalue()

    def test_preview_is_read_only_and_reports_plans(self):
        records = copy.deepcopy(self.api.records)
        settings = copy.deepcopy(self.api.settings)
        output = self.reconcile("--dry-run", "--prune")
        self.assertEqual(self.api.writes(), [])
        self.assertEqual(self.api.records, records)
        self.assertEqual(self.api.settings, settings)
        self.assertIn("Would create A create.example.test", output)
        self.assertIn("Would update A update.example.test", output)
        self.assertIn("Would delete A stale.example.test", output)
        self.assertIn("1 creations, 1 updates, 1 deletions planned", output)
        self.assertIn("No changes applied.", output)
        self.assertNotIn("DNS Sync Complete", output)

    def test_pruning_is_scoped_and_repeat_apply_is_idempotent(self):
        output = self.reconcile("--prune")
        self.assertIn("1 created, 1 updated, 1 unchanged, 1 stale, 1 deleted", output)
        names = {item["name"] for item in self.api.records}
        self.assertNotIn("stale.example.test", names)
        self.assertTrue({"manual.example.test", "_acme-challenge.example.test", "outside.other.test"} <= names)
        self.assertEqual(self.api.settings, self.spec["settings"])
        self.api.calls.clear()
        output = self.reconcile("--prune")
        self.assertEqual(self.api.writes(), [])
        self.assertIn("0 created, 0 updated, 3 unchanged, 0 stale, 0 deleted", output)

    def test_pruning_remains_opt_in_for_operational_cli(self):
        output = self.reconcile()
        self.assertIn("re-run with --prune to delete", output)
        self.assertFalse(any(call[0] == "DELETE" for call in self.api.calls))

    def test_type_replacement_deletes_stale_cname_first(self):
        self.api.records.append(record("create.example.test", "old.example.test", kind="CNAME") | {"id": "old-cname"})
        self.reconcile("--prune")
        deletion = next(index for index, call in enumerate(self.api.calls) if call[:2] == ("DELETE", "/zones/zone/dns_records/old-cname"))
        creation = next(index for index, call in enumerate(self.api.calls) if call[0] == "POST")
        self.assertLess(deletion, creation)

    def test_api_failure_cannot_report_success(self):
        def failing_api(token, endpoint, method="GET", data=None):
            if method == "POST":
                raise SystemExit("fixture: Cloudflare write failed")
            return self.api.request(token, endpoint, method, data)

        with self.assertRaisesRegex(SystemExit, "Cloudflare write failed"):
            self.reconcile("--prune", api=failing_api)

    def activation(self, executable, *arguments, status=0):
        log = self.root / "calls"
        log.unlink(missing_ok=True)
        result = subprocess.run(
            [executable, *arguments],
            env=os.environ | {"CALL_LOG": str(log), "RECONCILER_EXIT": str(status)},
            capture_output=True,
            text=True,
        )
        return result, log

    def test_activation_switch_uses_pruning_and_propagates_exit_status(self):
        for status in [0, 17]:
            with self.subTest(status=status):
                result, log = self.activation(fixture, "switch", status=status)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(log.read_text().splitlines(), ["--prune"])

    def test_both_artifacts_reject_unsupported_actions_before_reconciliation(self):
        for executable in [fixture, published]:
            for arguments in [[], ["boot"], ["test"], ["rollback"], ["unknown"], ["switch", "--dry-run"]]:
                with self.subTest(executable=executable, arguments=arguments):
                    result, log = self.activation(executable, *arguments)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertTrue(result.stderr)
                    self.assertFalse(log.exists(), "unsupported action invoked the reconciler")


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
