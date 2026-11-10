"""A switch must preserve interactive state and rotate only changed declared credentials."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


settings = load("settings", sys.argv.pop(1))
credentials = load("credentials", sys.argv.pop(1))


class State(unittest.TestCase):
    def test_switch_preserves_runtime_state_and_removes_retired_peers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            initial = {
                "theme": "custom",
                "desktopDefaultHostId": "nixfiles:old",
                "fallbackModel": "custom/model",
                "accountSwitchProviders": ["other"],
                "desktopSshInstances": [
                    {"id": "manual", "sshCommand": "ssh mine"},
                    {"id": "nixfiles:old"},
                    {"id": "nixfiles:peer", "auth": {"sshPassword": "fixture"}},
                ],
                "desktopHosts": [
                    {"id": "manual", "url": "http://mine"},
                    {"id": "nixfiles:old"},
                    {"id": "nixfiles:peer", "url": "http://127.0.0.1:4567", "clientToken": "fixture"},
                ],
            }
            path.write_text(json.dumps(initial))
            desired = {
                "desktopSshInstances": [{"id": "nixfiles:peer", "sshCommand": "ssh peer"}],
                "desktopHosts": [{"id": "nixfiles:peer", "label": "peer", "url": "http://127.0.0.1/"}],
            }
            settings.reconcile(path, desired)
            first = json.loads(path.read_text())
            settings.reconcile(path, desired)
            self.assertEqual(first, json.loads(path.read_text()))
            self.assertEqual(first["theme"], "custom")
            self.assertEqual(first["desktopDefaultHostId"], "local")
            self.assertEqual(first["fallbackModel"], "custom/model")
            self.assertEqual(first["accountSwitchProviders"], ["other"])
            self.assertEqual(first["desktopSshInstances"][0], initial["desktopSshInstances"][0])
            self.assertEqual(first["desktopSshInstances"][1]["auth"], {"sshPassword": "fixture"})
            self.assertEqual(first["desktopHosts"][1]["url"], "http://127.0.0.1:4567")
            self.assertEqual(first["desktopHosts"][1]["clientToken"], "fixture")
            self.assertNotIn("nixfiles:old", path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_invalid_state_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text("{broken")
            with self.assertRaises(ValueError):
                settings.reconcile(path, {})
            self.assertEqual(path.read_text(), "{broken")

    def test_credential_rotation_preserves_healthy_selection_and_manual_accounts(self):
        stored = {
            "manual": {"id": "manual", "integrationID": "opencode", "label": "mine", "value": {"type": "key", "key": "manual"}, "active": True},
            "cred_nixfiles_go_one": {"id": "cred_nixfiles_go_one", "label": "one", "value": {"type": "key", "key": "old"}, "active": False},
            "cred_nixfiles_go_retired": {"id": "cred_nixfiles_go_retired", "active": False},
        }
        calls = []
        reject = {"create": False}
        profile = {"accountSwitchProviders": ["other"], "fallbackModel": "manual/model"}

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                calls.append(("GET", self.path))
                self.send_response(200)
                self.end_headers()
                connections = sorted(stored.values(), key=lambda item: not item["active"])
                payload = profile if self.path == "/api/config/settings" else {"data": {
                    "connections": [{"id": item["id"], "label": item.get("label", ""), "type": "credential"}
                                    for item in connections]}}

                self.wfile.write(json.dumps(payload).encode())

            def do_PUT(self):
                calls.append(("PUT", self.path))
                profile.update(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                self.send_response(204)
                self.end_headers()

            def do_DELETE(self):
                calls.append(("DELETE", self.path))
                stored.pop(self.path.rsplit("/", 1)[-1], None)
                self.send_response(204)
                self.end_headers()

            def do_POST(self):
                calls.append(("POST", self.path))
                item = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if reject["create"]:
                    self.send_response(503)
                    self.end_headers()
                    return
                item["active"] = item.pop("activate")
                stored[item["id"]] = item
                self.send_response(204)
                self.end_headers()

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                key = Path(directory) / "key"
                key.write_text("rotated\n")
                plan = [{"name": "one", "path": str(key)}]
                base = f"http://127.0.0.1:{server.server_port}"
                credentials.reconcile(base, plan)
                replacement = next(item for key, item in stored.items() if key.startswith("cred_nixfiles_go_one_"))
                self.assertEqual(replacement["value"]["key"], "rotated")
                self.assertFalse(replacement["active"])
                self.assertLess(next(i for i, call in enumerate(calls) if call[0] == "POST"),
                                next(i for i, call in enumerate(calls) if call[0] == "DELETE"))
                self.assertTrue(stored["manual"]["active"])
                self.assertNotIn("cred_nixfiles_go_retired", stored)
                calls.clear()
                credentials.reconcile(base, plan)
                self.assertEqual(calls, [("GET", "/api/integration/opencode"), ("GET", "/api/config/settings")])
                self.assertEqual(profile, {"accountSwitchProviders": ["opencode-go", "other"], "fallbackModel": "manual/model"})
                before = json.loads(json.dumps(stored))
                key.write_text("another-key")
                reject["create"] = True
                with self.assertRaises(credentials.urllib.error.HTTPError) as caught:
                    credentials.reconcile(base, plan)
                caught.exception.close()
                self.assertEqual(stored, before)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


unittest.main()
