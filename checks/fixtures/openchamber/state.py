"""A switch must preserve interactive state and rotate only changed declared credentials."""
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
        reject = False

        def run(arguments, payload=None):
            calls.append(arguments)
            if arguments[0] == 'list':
                rows = sorted(stored.values(), key=lambda item: not item['active'])
                return json.dumps([{'id': 'opencode', 'connections': [
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
