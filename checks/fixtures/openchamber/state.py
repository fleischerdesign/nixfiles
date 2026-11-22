"""A switch must preserve interactive state and rotate only changed declared credentials."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


settings = load("settings", sys.argv.pop(1))
credentials = load("credentials", sys.argv.pop(1))
pair = load("pair", sys.argv.pop(1))


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
            inode = path.stat().st_ino
            settings.reconcile(path, desired)
            self.assertEqual(path.stat().st_ino, inode)
            self.assertEqual(first, json.loads(path.read_text()))
            self.assertEqual(first["theme"], "custom")
            self.assertEqual(first["desktopDefaultHostId"], "local")
            self.assertEqual(first["fallbackModel"], "custom/model")
            self.assertEqual(first["accountSwitchProviders"], ["other"])
            self.assertEqual(first["desktopSshInstances"][0], initial["desktopSshInstances"][0])
            self.assertEqual(first["desktopSshInstances"][1]["auth"], {"sshPassword": "fixture"})
            self.assertEqual(first["desktopHosts"][1]["url"], "http://127.0.0.1/")
            self.assertEqual(first["desktopHosts"][1]["clientToken"], "fixture")
            self.assertNotIn("nixfiles:old", path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_native_migration_drops_the_old_ssh_token_once(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'settings.json'
            path.write_text(json.dumps({
                'desktopSshInstances': [{'id': 'nixfiles:peer'}],
                'desktopHosts': [{'id': 'nixfiles:peer', 'url': 'http://127.0.0.1:4567', 'clientToken': 'old-ssh'}],
            }))
            desired = {'desktopSshInstances': [], 'desktopHosts': [
                {'id': 'nixfiles:peer', 'url': 'http://peer:7337'}]}
            settings.reconcile(path, desired)
            migrated = json.loads(path.read_text())
            self.assertNotIn('clientToken', migrated['desktopHosts'][0])
            self.assertEqual(migrated['desktopSshInstances'], [])
            migrated['desktopHosts'][0]['clientToken'] = 'new-native'
            path.write_text(json.dumps(migrated))
            settings.reconcile(path, desired)
            self.assertEqual(json.loads(path.read_text())['desktopHosts'][0]['clientToken'], 'new-native')

    def test_password_secret_and_default_host_are_applied(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            secret = Path(directory) / "password"
            secret.write_text("known-password\n")
            desired = {
                "desktopSshInstances": [],
                "desktopHosts": [{"id": "nixfiles:peer", "url": "http://peer:7337"}],
                "desktopLocalPort": 7337,
                "desktopLanAccessEnabled": True,
                "desktopDefaultHostId": "nixfiles:peer",
                "desktopUiPasswordPath": str(secret),
            }
            settings.reconcile(path, desired)
            current = json.loads(path.read_text())
            self.assertEqual(current["desktopUiPassword"], "known-password")
            self.assertEqual(current["desktopDefaultHostId"], "nixfiles:peer")
            self.assertNotIn("desktopUiPasswordPath", current)
            desired["desktopUiPasswordPath"] = None
            settings.reconcile(path, desired)
            self.assertEqual(json.loads(path.read_text())["desktopUiPassword"], "known-password")

    def test_removed_managed_peer_is_queued_for_revocation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text(json.dumps({
                "desktopHosts": [{
                    "id": "nixfiles:old", "url": "http://old:7337",
                    "apiUrl": "http://old:7337", "clientToken": "old-token",
                }],
            }))
            settings.reconcile(path, {
                "desktopSshInstances": [], "desktopHosts": [],
            })
            current = json.loads(path.read_text())
            self.assertEqual(current["desktopHosts"], [])
            self.assertEqual(current["nixfilesPendingRevocations"][0]["id"], "nixfiles:old")
            self.assertEqual(current["nixfilesPendingRevocations"][0]["clientToken"], "old-token")

    def test_pair_bootstraps_and_creates_a_desktop_client(self):
        calls = []

        def fake_request(base, route, token=None, payload=None, method=None):
            calls.append((route, token, payload, method))
            if route == '/health':
                return {'runtime': 'desktop'}
            if route == '/auth/session':
                return {'clientToken': 'short'}
            if route == '/api/client-auth/clients' and token == 'short':
                return {'token': 'local-token'}
            if route == '/api/client-auth/clients' and token == 'local-token':
                return {'token': 'peer-token'}
            raise AssertionError(route)

        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'openchamber'
            config.mkdir()
            path = config / 'settings.json'
            path.write_text(json.dumps({'desktopLocalPort': 7337, 'desktopUiPassword': 'pw'}))
            with mock.patch.dict(os.environ, {'XDG_CONFIG_HOME': directory}), \
                    mock.patch.object(pair, 'request', fake_request):
                current = pair.read_settings(pair.settings_path())
                token = pair.bootstrap_token(current, 'http://127.0.0.1:7337')
                self.assertEqual(token, 'local-token')
                self.assertEqual(json.loads(path.read_text())['desktopLocalClientToken'], 'local-token')
                with mock.patch.object(pair, 'ensure_local_token', lambda _: 'local-token'):
                    result = pair.issue({'peers': {'peer': {}}, 'host': 'source'}, 'peer')
                self.assertEqual(result, {'clientToken': 'peer-token'})
                create = [
                    call for call in calls
                    if call[0] == '/api/client-auth/clients'
                    and call[2] and call[2].get('clientKind') == 'desktop'
                ]
                self.assertEqual(create[0][2]['dedupeKey'], 'nixfiles:peer')

    def test_pair_keeps_only_unrevoked_pending_peers(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'openchamber'
            config.mkdir()
            path = config / 'settings.json'
            path.write_text(json.dumps({
                'nixfilesPendingRevocations': [
                    {'id': 'nixfiles:a', 'url': 'http://a:7337', 'clientToken': 'a-token'},
                    {'id': 'nixfiles:b', 'url': 'http://b:7337', 'clientToken': 'b-token'},
                ],
            }))
            with mock.patch.dict(os.environ, {'XDG_CONFIG_HOME': directory}), \
                    mock.patch.object(pair, 'revoke_peer', lambda entry: entry['id'] == 'nixfiles:a'):
                pair.reconcile({'peers': {}, 'host': 'source'})
            pending = json.loads(path.read_text())['nixfilesPendingRevocations']
            self.assertEqual([item['id'] for item in pending], ['nixfiles:b'])

    def test_invalid_state_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text("{broken")
            with self.assertRaises(ValueError):
                settings.reconcile(path, {})
            self.assertEqual(path.read_text(), "{broken")

    def test_credential_rotation_preserves_healthy_selection_and_manual_accounts(self):
        stored = {
            "manual": {"id": "manual", "integrationID": "opencode-go", "label": "mine", "value": {"type": "key", "key": "manual"}, "active": True},
            "cred_nixfiles_go_one": {"id": "cred_nixfiles_go_one", "label": "one", "value": {"type": "key", "key": "old"}, "active": False},
            "cred_nixfiles_go_retired": {"id": "cred_nixfiles_go_retired", "active": False},
        }
        calls = []
        reject = False

        def run(arguments, payload=None):
            calls.append(arguments)
            if arguments[0] == 'list':
                rows = sorted(stored.values(), key=lambda item: not item['active'])
                return json.dumps([{'id': 'opencode-go', 'connections': [
                    {'id': item['id'], 'label': item.get('label', ''), 'type': 'credential'}
                    for item in rows]}])
            if arguments[0] == 'import':
                if reject:
                    raise RuntimeError('Import failed')
                for item in json.loads(payload):
                    stored[item['id']] = item
            if arguments[0] == 'logout':
                del stored[arguments[2]]
            if arguments[0] == 'switch':
                for item in stored.values():
                    item['active'] = item['id'] == arguments[2]
            return ''

        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory)/'key'
            key.write_text('rotated\n')
            plan = [{'name': 'one', 'path': str(key)}]
            credentials.reconcile(plan, run)
            replacement = next(item for name, item in stored.items() if name.startswith('cred_nixfiles_go_one_'))
            self.assertEqual(replacement['value']['key'], 'rotated')
            self.assertTrue(stored['manual']['active'])
            self.assertNotIn('cred_nixfiles_go_retired', stored)
            self.assertLess(next(i for i,c in enumerate(calls) if c[0]=='import'),
                            next(i for i,c in enumerate(calls) if c[0]=='logout'))
            calls.clear()
            credentials.reconcile(plan, run)
            self.assertEqual(calls, [['list', '--format', 'json']])
            for item in stored.values():
                item['active'] = item['id'] == replacement['id']
            key.write_text('second')
            credentials.reconcile(plan, run)
            selected = next(item for item in stored.values() if item['active'])
            self.assertEqual(selected['value']['key'], 'second')
            before = json.loads(json.dumps(stored))
            key.write_text('third')
            reject = True
            with self.assertRaises(RuntimeError):
                credentials.reconcile(plan, run)
            self.assertEqual(stored, before)


unittest.main()
