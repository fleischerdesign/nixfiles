"""Enroll declared desktops with OpenChamber's pairing API; SSH only bootstraps trust."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def request(base, route, token=None, payload=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(base + route, headers=headers,
                                 data=json.dumps(payload).encode() if payload is not None else None)
    with http.open(req, timeout=4) as response:
        return json.load(response)


def write(path, value):
    if path.exists() and json.loads(path.read_text()) == value:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix='.nixfiles-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as handle:
            json.dump(value, handle, indent=2)
            handle.write('\n')
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def issue(plan, source):
    if source not in plan['peers']:
        raise ValueError('Device is not a declared peer')
    settings = json.loads((Path.home()/'.config/openchamber/settings.json').read_text())
    base = 'http://127.0.0.1:' + str(settings['desktopLocalPort'])
    if request(base, '/health').get('runtime') != 'desktop':
        raise ValueError('Desktop is not running')
    token = settings.get('desktopLocalClientToken')
    pairing = request(base, '/api/client-auth/pairing/sessions', token, {
        'label': source, 'allowedClientKinds': ['desktop'],
        'includeRelay': False, 'includeDirect': True,
    })['pairing']
    result = request(base, '/api/client-auth/pairing/redeem', payload={
        'pairingId': pairing['id'], 'secret': pairing['secret'],
        'clientLabel': source, 'clientKind': 'desktop', 'deviceName': source,
        'devicePlatform': 'linux', 'dedupeKey': 'nixfiles:' + source,
    })
    return {'clientToken': result['clientToken']}


def reconcile(plan):
    path = Path.home()/'.config/openchamber/settings.json'
    current = json.loads(path.read_text()) if path.exists() else {}
    existing = {item['id']: item for item in current.get('desktopHosts', [])}
    enrolled = {}
    for name, peer in plan['peers'].items():
        identifier = 'nixfiles:' + name
        base = 'http://' + peer['address'] + ':' + str(peer['port'])
        previous = existing.get(identifier, {})
        token = previous.get('clientToken')
        issued = False
        try:
            if not token:
                raise ValueError('Not enrolled')
            request(base, '/api/config/settings', token)
        except (OSError, ValueError, urllib.error.URLError):
            if token:
                print('OpenChamber peer offline or token revoked: ' + name, file=sys.stderr)
                enrolled[identifier] = {'id': identifier, 'label': name, 'url': base, 'apiUrl': base}
                continue
            # Check reachability before asking the peer to issue a token. Offline devices
            # retain their saved token and are retried by the next enrollment run.
            try:
                if request(base, '/health').get('runtime') != 'desktop':
                    raise ValueError('Not a desktop runtime')
                result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=4',
                                         '-p', str(peer['sshPort']), peer['user']+'@'+peer['address'],
                                         'openchamber-fleet-pair', '--issue', plan['host']],
                                        capture_output=True, text=True, timeout=20)
                if result.returncode:
                    raise RuntimeError('Enrollment unavailable')
                token = json.loads(result.stdout)['clientToken']
                request(base, '/api/config/settings', token)
                issued = True
                print('Paired OpenChamber desktop: ' + name)
            except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired):
                print('OpenChamber peer unavailable for enrollment: ' + name, file=sys.stderr)
                token = previous.get('clientToken')
        enrolled[identifier] = {'id': identifier, 'label': name, 'url': base, 'apiUrl': base}
        if issued:
            enrolled[identifier]['clientToken'] = token
    # Re-read after network calls to keep changes the desktop made while enrollment ran.
    current = json.loads(path.read_text()) if path.exists() else {}
    latest = {item['id']: item for item in current.get('desktopHosts', [])}
    current['desktopHosts'] = [item for item in current.get('desktopHosts', [])
                               if not item.get('id', '').startswith('nixfiles:')] + [
        latest.get(identifier, {}) | value for identifier, value in enrolled.items()]
    current['desktopSshInstances'] = [item for item in current.get('desktopSshInstances', [])
                                      if not item.get('id', '').startswith('nixfiles:')]
    default = current.get('desktopDefaultHostId', '')
    if default.startswith('nixfiles:') and default not in enrolled:
        current['desktopDefaultHostId'] = 'local'
    write(path, current)


if __name__ == '__main__':
    try:
        plan = json.loads(Path(sys.argv[1]).read_text())
        if len(sys.argv) == 4 and sys.argv[2] == '--issue':
            print(json.dumps(issue(plan, sys.argv[3])))
        else:
            reconcile(plan)
    except Exception as error:
        # Pairing secrets and client tokens must never enter the journal.
        print(f'OpenChamber enrollment failed ({type(error).__name__})', file=sys.stderr)
        sys.exit(1)
