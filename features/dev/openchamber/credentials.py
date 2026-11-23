"""Reconcile this device's Go credentials with OpenCode's public, standalone CLI."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys

CREDENTIAL_PREFIX = 'cred_nixfiles_go_'
# A device exposes whichever integration its provider catalog knows: some list `opencode`
# (the Console) and carry the declared keys there, others only `opencode-go` (Go). The
# integration that already holds declared keys decides; the order only settles a first run.
INTEGRATION_IDS = ('opencode', 'opencode-go')


def credential_integrations(integrations):
    return [
        (item['id'], [connection for connection in item.get('connections', [])
                      if connection['type'] == 'credential'])
        for item in integrations
    ]


def resolve_integration(integrations):
    stores = credential_integrations(integrations)
    owned = [
        (integration_id, connections) for integration_id, connections in stores
        if any(item['id'].startswith(CREDENTIAL_PREFIX) for item in connections)
    ]
    if owned:
        return max(owned, key=lambda store: len(store[1]))
    for candidate in INTEGRATION_IDS:
        for integration_id, connections in stores:
            if integration_id == candidate:
                return integration_id, connections
    raise RuntimeError('OpenCode exposes no integration for the declared Go keys')


def reconcile(subscriptions, run):
    integrations = json.loads(run(['list', '--format', 'json']))
    integration_id, credentials = resolve_integration(integrations)
    # OpenCode lists the selected credential first in `auth list --format json`.
    active = credentials[0].get('id') if credentials else None
    stored = {item['id']: item for item in credentials}
    desired = []
    replacements = []
    for subscription in subscriptions:
        key = Path(subscription['path']).read_text().strip()
        if not key:
            raise ValueError('Empty Go credential')
        fingerprint = hashlib.sha256(key.encode()).hexdigest()[:16]
        credential_id = CREDENTIAL_PREFIX + subscription['name'] + '_' + fingerprint
        desired.append({'id': credential_id, 'integrationID': integration_id,
                        'label': subscription['name'], 'active': False,
                        'value': {'type': 'key', 'key': key}})
        old = next((item for item in stored.values()
                    if item['id'].startswith(CREDENTIAL_PREFIX)
                    and item.get('label') == subscription['name']), None)
        if credential_id not in stored and old and old['id'] == active:
            replacements.append(credential_id)
    # Import every replacement before switching or deleting any old credential.
    missing = [item for item in desired if item['id'] not in stored]
    if missing:
        run(['import'], json.dumps(missing))
        integrations = json.loads(run(['list', '--format', 'json']))
        integration_id, credentials = resolve_integration(integrations)
        stored = {item['id']: item for item in credentials}
        absent = [item['id'] for item in missing if item['id'] not in stored]
        if absent:
            raise RuntimeError('OpenCode did not store the imported keys in ' + integration_id)
    for credential_id in replacements:
        run(['switch', integration_id, credential_id])
    wanted = {item['id'] for item in desired}
    for credential_id in sorted(stored.keys() - wanted):
        if credential_id.startswith(CREDENTIAL_PREFIX):
            run(['logout', integration_id, credential_id])


def cli(binary):
    def run(arguments, payload=None):
        result = subprocess.run([binary, 'auth', *arguments, '--standalone'],
                                input=payload, capture_output=True, text=True, timeout=90)
        if result.returncode:
            # CLI output can contain a submitted key; never include it in an exception.
            raise RuntimeError('OpenCode auth ' + arguments[0] + ' failed')
        return result.stdout
    return run


if __name__ == '__main__':
    try:
        reconcile(json.loads(Path(sys.argv[2]).read_text()), cli(sys.argv[1]))
    except Exception as error:
        print(f'OpenChamber Go reconciliation failed ({type(error).__name__})', file=sys.stderr)
        sys.exit(1)
