"""Exercise reconciliation against real, isolated OpenChamber HTTP servers."""

import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

SERVER = Path(sys.argv.pop(1))
NODE = sys.argv.pop(1)
spec = importlib.util.spec_from_file_location("reconcile", Path(__file__).with_name("reconcile.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
PASSWORD = "isolated-openchamber-test-password"


class Server:
    def __init__(self, root):
        root.mkdir()
        self.root = root
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            self.port = listener.getsockname()[1]
        self.url = f"http://127.0.0.1:{self.port}"
        self.log = (root / "server.log").open("w+")
        self.process = subprocess.Popen(
            [NODE, str(SERVER), "--host", "127.0.0.1", "--port", str(self.port), "--api-only"],
            env={**os.environ, "HOME": str(root), "OPENCHAMBER_DATA_DIR": str(root / "data"),
                 "XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "share"),
                 "XDG_STATE_HOME": str(root / "state"), "XDG_CACHE_HOME": str(root / "cache"),
                 "OPENCHAMBER_UI_PASSWORD": PASSWORD, "OPENCODE_JWT_SECRET": "isolated-test-jwt-secret-which-is-long-enough",
                 "OPENCODE_SKIP_START": "true", "OPENCHAMBER_RELAY_HOST": "off"},
            cwd=root, stdout=self.log, stderr=subprocess.STDOUT,
        )
        self.api = module.Api(self.url, PASSWORD, timeout=1)
        for _ in range(100):
            try:
                self.api.login()
                return
            except (module.Pending, module.ApiError):
                if self.process.poll() is not None:
                    break
                time.sleep(0.1)
        self.log.seek(0)
        self.close()
        raise RuntimeError("Isolated OpenChamber failed to start: " + self.log.read())

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()

    def clients(self):
        self.api.login()
        return self.api.request("/api/client-auth/clients")["clients"]


class ReconcileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.server = Server(self.root / "server")
        self.addCleanup(self.server.log.close)
        self.addCleanup(self.server.close)
        self.state = self.root / "private/state.json"
        self.manifest = {"client": "pc", "hosts": [{"name": "server", "url": self.server.url}], "server": None}

    def sync(self, manifest=None):
        return module.reconcile(manifest or self.manifest, self.state, PASSWORD, timeout=0.25)

    def read_state(self):
        return json.loads(self.state.read_text())

    def test_create_reuse_revoke_restore_and_remove(self):
        self.assertEqual(self.sync(), 0)
        first = self.read_state()["connections"]["server"]
        self.assertTrue(self.server.api.valid(first["token"]))
        self.assertEqual(self.sync(), 0)
        self.assertEqual(first, self.read_state()["connections"]["server"])
        self.assertEqual(len(self.server.clients()), 1)
        self.server.api.revoke(first["clientId"])
        self.assertFalse(self.server.api.valid(first["token"]))
        self.assertEqual(self.sync(), 0)
        replacement = self.read_state()["connections"]["server"]
        self.assertNotEqual(first["token"], replacement["token"])
        self.assertEqual(len(self.server.clients()), 1)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.state.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.sync({**self.manifest, "hosts": []}), 0)
        self.assertFalse(self.server.api.valid(replacement["token"]))
        self.assertEqual(self.read_state()["connections"], {})
        self.assertEqual(self.read_state()["retired"], {})

    def test_target_prunes_only_obsolete_managed_grants(self):
        self.sync()
        self.server.api.login()
        phone = self.server.api.request("/api/client-auth/clients", "POST", {"label": "Phone", "clientKind": "mobile"})
        manual = self.server.api.request("/api/client-auth/clients", "POST", {"label": "Personal desktop", "clientKind": "desktop"})
        target = {"client": "server", "hosts": [], "server": {"url": self.server.url, "clients": ["pc"]}}
        self.assertEqual(module.reconcile(target, self.root / "target/state.json", PASSWORD), 0)
        token = self.read_state()["connections"]["server"]["token"]
        self.assertTrue(self.server.api.valid(token))
        target["server"]["clients"] = []
        self.assertEqual(module.reconcile(target, self.root / "target/state.json", PASSWORD), 0)
        self.assertFalse(self.server.api.valid(token))
        self.assertTrue(self.server.api.valid(phone["token"]))
        self.assertTrue(self.server.api.valid(manual["token"]))

    def test_offline_peer_does_not_block_other_targets_or_lose_retirement(self):
        self.sync()
        first = self.read_state()["connections"]["server"]
        self.server.close()
        second = Server(self.root / "second")
        self.addCleanup(second.log.close)
        self.addCleanup(second.close)
        self.assertEqual(self.sync({**self.manifest, "hosts": [{"name": "second", "url": second.url}]}), 0)
        state = self.read_state()
        self.assertNotIn("server", state["connections"])
        self.assertIn("second", state["connections"])
        self.assertEqual(len(state["retired"]), 1)
        self.assertNotIn("token", next(iter(state["retired"].values())))
        self.assertIn("pending", state["status"]["retire:" + self.server.url])
        # Re-use the original service's persistent data and port after an outage.
        self.server.process = subprocess.Popen(
            [NODE, str(SERVER), "--host", "127.0.0.1", "--port", str(self.server.port), "--api-only"],
            env={**os.environ, "HOME": str(self.server.root), "OPENCHAMBER_DATA_DIR": str(self.server.root / "data"),
                 "OPENCHAMBER_UI_PASSWORD": PASSWORD, "OPENCODE_JWT_SECRET": "isolated-test-jwt-secret-which-is-long-enough",
                 "OPENCODE_SKIP_START": "true", "OPENCHAMBER_RELAY_HOST": "off"},
            cwd=self.server.root, stdout=self.server.log, stderr=subprocess.STDOUT,
        )
        for _ in range(100):
            try:
                self.server.api.login()
                break
            except module.Pending:
                time.sleep(0.1)
        self.assertEqual(self.sync({**self.manifest, "hosts": [{"name": "second", "url": second.url}]}), 0)
        self.assertEqual(self.read_state()["retired"], {})
        self.assertFalse(self.server.api.valid(first["token"]))

    def test_bad_credentials_and_corrupt_state_fail_loudly(self):
        self.assertEqual(module.reconcile(self.manifest, self.state, "wrong-password"), 1)
        self.assertEqual(self.read_state()["connections"], {})
        self.state.write_text("broken json")
        with self.assertRaises(json.JSONDecodeError):
            self.sync()
        self.assertEqual(self.state.read_text(), "broken json")

    def test_each_client_target_pair_has_an_independent_token(self):
        self.sync()
        other = self.root / "notebook/state.json"
        self.assertEqual(module.reconcile({**self.manifest, "client": "notebook"}, other, PASSWORD), 0)
        first = self.read_state()["connections"]["server"]
        second = json.loads(other.read_text())["connections"]["server"]
        self.assertNotEqual(first["token"], second["token"])
        self.server.api.revoke(first["clientId"])
        self.assertTrue(self.server.api.valid(second["token"]))


if __name__ == "__main__":
    unittest.main()
