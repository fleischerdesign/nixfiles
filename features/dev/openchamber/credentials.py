"""Reconcile this device's Go credentials with OpenCode's public, standalone CLI."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys

# OpenCode registers its Console service-account keys under the integration id `opencode`;
# `opencode-go` only names the provider that carries its models, and appears in `auth list`
# as an environment-variable connection with no credentials of its own.
INTEGRATION_ID = 'opencode'


def integration_connections(integrations):
    integration = next((item for item in integrations if item['id'] == INTEGRATION_ID), None)
    if integration is None:
        return None, []
    return integration, integration.get('connections', [])


def reconcile(subscriptions, run):
    integrations = json.loads(run(['list', '--format', 'json']))
    _, connections = integration_connections(integrations)
    credentials = [item for item in connections if item['type'] == 'credential']
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
        credential_id = 'cred_nixfiles_go_' + subscription['name'] + '_' + fingerprint
        desired.append({'id': credential_id, 'integrationID': INTEGRATION_ID,
                        'label': subscription['name'], 'active': False,
                        'value': {'type': 'key', 'key': key}})
        old = next((item for item in stored.values()
                    if item['id'].startswith('cred_nixfiles_go_')
                    and item.get('label') == subscription['name']), None)
        if credential_id not in stored and old and old['id'] == active:
            replacements.append(credential_id)
    # Import every replacement before switching or deleting any old credential.
    missing = [item for item in desired if item['id'] not in stored]
    if missing:
        run(['import'], json.dumps(missing))
        integrations = json.loads(run(['list', '--format', 'json']))
        integration, connections = integration_connections(integrations)
        if integration is None:
            raise RuntimeError('OpenCode integration ' + INTEGRATION_ID + ' is missing after import')
        stored = {item['id']: item for item in connections if item['type'] == 'credential'}
    for credential_id in replacements:
        run(['switch', INTEGRATION_ID, credential_id])
    wanted = {item['id'] for item in desired}
    for credential_id in sorted(stored.keys() - wanted):
        if credential_id.startswith('cred_nixfiles_go_'):
            run(['logout', INTEGRATION_ID, credential_id])


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
