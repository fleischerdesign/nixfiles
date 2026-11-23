"""Enroll declared desktops with OpenChamber's local admin API; SSH only bootstraps trust."""

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


MANAGED_PREFIXES = ('nixfiles:', 'nixfiles-server:')


def is_managed(identifier):
    return isinstance(identifier, str) and identifier.startswith(MANAGED_PREFIXES)


def settings_path():
    config_home = os.environ.get('XDG_CONFIG_HOME')
    root = Path(config_home) if config_home else Path.home()/'.config'
    return root/'openchamber/settings.json'


@contextmanager
def settings_lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.parent/'.settings.lock'
    with open(lock_path, 'a') as handle:
        os.chmod(lock_path, 0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def read_settings(path):
    return json.loads(path.read_text()) if path.exists() else {}


def write_settings(path, value):
    if path.exists() and json.loads(path.read_text()) == value:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix='.nixfiles-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as handle:
            json.dump(value, handle, indent=2)
            handle.write('\n')
        os.replace(name, path)
        os.chmod(path, 0o600)
    finally:
        Path(name).unlink(missing_ok=True)


def request(base, route, token=None, payload=None, method=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(
        base + route, headers=headers,
        data=json.dumps(payload).encode() if payload is not None else None,
        method=method,
    )
    with http.open(req, timeout=4) as response:
        return json.load(response)


def bootstrap_token(settings, base):
    password = settings.get('desktopUiPassword')
    if not password:
        raise ValueError('Desktop requires authentication but has no UI password')
    short = request(base, '/auth/session', payload={
        'password': password, 'trustDevice': False, 'issueClientToken': True,
        'clientLabel': 'nixfiles-enrollment', 'clientKind': 'desktop-local',
        'dedupeKey': 'nixfiles-bootstrap',
    }).get('clientToken')
    if not short:
        raise ValueError('Desktop did not issue a bootstrap token')
    result = request(base, '/api/client-auth/clients', short, {
        'label': 'nixfiles-enrollment', 'clientKind': 'desktop-local',
        'dedupeKey': 'nixfiles-enrollment',
    })
    token = result.get('token')
    if not token:
        raise ValueError('Desktop did not create a local client')
    path = settings_path()
    with settings_lock(path):
        current = read_settings(path)
        current['desktopLocalClientToken'] = token
        write_settings(path, current)
    return token


def ensure_local_token(settings):
    if not settings.get('desktopUiPassword'):
        return None
    try:
        base = 'http://127.0.0.1:' + str(settings['desktopLocalPort'])
        if request(base, '/health').get('runtime') != 'desktop':
            return None
    except (OSError, ValueError, KeyError, urllib.error.URLError):
        return None
    token = settings.get('desktopLocalClientToken')
    if token:
        try:
            request(base, '/api/config/settings', token)
            return token
        except urllib.error.HTTPError as error:
            if error.code not in (401, 403):
                return token
        except (OSError, ValueError, urllib.error.URLError):
            return token
    try:
        return bootstrap_token(settings, base)
    except Exception as error:
        print(f'OpenChamber local token bootstrap failed ({type(error).__name__})', file=sys.stderr)
        return None


def revoke_peer(entry):
    token = entry.get('clientToken')
    base = entry.get('apiUrl') or entry.get('url')
    if not token or not base:
        return True
    try:
        clients = request(base, '/api/client-auth/clients', token).get('clients', [])
        for client in clients:
            client_id = client.get('id')
            if client_id:
                request(base, '/api/client-auth/clients/' + client_id, token, method='DELETE')
    except urllib.error.HTTPError as error:
        return error.code in (401, 403, 404)
    except (OSError, ValueError, KeyError, urllib.error.URLError):
        return False
    return True


def issue(plan, source):
    if source not in plan['peers']:
        raise ValueError('Device is not a declared peer')
    settings = read_settings(settings_path())
    base = 'http://127.0.0.1:' + str(settings['desktopLocalPort'])
    if request(base, '/health').get('runtime') != 'desktop':
        raise ValueError('Desktop is not running')
    token = ensure_local_token(settings)
    result = request(base, '/api/client-auth/clients', token, {
        'label': source, 'clientKind': 'desktop', 'dedupeKey': 'nixfiles:' + source,
    })
    return {'clientToken': result['token']}


def reconcile(plan):
    path = settings_path()
    current = read_settings(path)
    if not isinstance(current, dict):
        raise ValueError('OpenChamber settings must be a JSON object')
    ensure_local_token(current)
    current = read_settings(path)
    pending = current.get('nixfilesPendingRevocations', [])
    remaining = [entry for entry in pending if isinstance(entry, dict) and not revoke_peer(entry)]
    revoked_ids = {entry.get('id') for entry in pending if entry not in remaining and isinstance(entry, dict)}
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
                enrolled[identifier] = {'id': identifier, 'label': name,
                                        'url': base, 'apiUrl': base,
                                        'clientToken': token}
                continue
            try:
                if request(base, '/health').get('runtime') != 'desktop':
                    raise ValueError('Not a desktop runtime')
                command = 'bash -lc ' + shlex.quote(
                    'exec openchamber-fleet-pair --issue ' + plan['host'])
                result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=4',
                                         '-p', str(peer['sshPort']), peer['user']+'@'+peer['address'],
                                         command],
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
    for name, peer in plan.get('serverPeers', {}).items():
        identifier = 'nixfiles-server:' + name
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
                print('OpenChamber server offline or token revoked: ' + name, file=sys.stderr)
                enrolled[identifier] = {'id': identifier, 'label': name,
                                        'url': base, 'apiUrl': base,
                                        'clientToken': token}
                continue
            try:
                command = 'bash -lc ' + shlex.quote(
                    'exec openchamber-server-enroll --issue ' + plan['host'])
                result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=4',
                                         '-p', str(peer['sshPort']), peer['user']+'@'+peer['address'],
                                         command],
                                        capture_output=True, text=True, timeout=20)
                if result.returncode:
                    raise RuntimeError('Enrollment unavailable')
                token = json.loads(result.stdout)['clientToken']
                request(base, '/api/config/settings', token)
                issued = True
                print('Paired OpenChamber server: ' + name)
            except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired):
                print('OpenChamber server unavailable for enrollment: ' + name, file=sys.stderr)
                token = previous.get('clientToken')
        enrolled[identifier] = {'id': identifier, 'label': name, 'url': base, 'apiUrl': base}
        if issued:
            enrolled[identifier]['clientToken'] = token
    with settings_lock(path):
        current = read_settings(path)
        latest = {item['id']: item for item in current.get('desktopHosts', [])}
        current['desktopHosts'] = [item for item in current.get('desktopHosts', [])
                                   if not is_managed(item.get('id', ''))] + [
            latest.get(identifier, {}) | value for identifier, value in enrolled.items()]
        current['desktopSshInstances'] = [item for item in current.get('desktopSshInstances', [])
                                          if not is_managed(item.get('id', ''))]
        default = current.get('desktopDefaultHostId', '')
        if is_managed(default) and default not in enrolled:
            current['desktopDefaultHostId'] = 'local'
        pending_now = current.get('nixfilesPendingRevocations', [])
        keep = {
            entry['id']: entry
            for entry in pending_now
            if isinstance(entry, dict) and entry.get('id') and entry['id'] not in revoked_ids
        }
        for entry in remaining:
            keep[entry['id']] = entry
        if keep:
            current['nixfilesPendingRevocations'] = list(keep.values())
        else:
            current.pop('nixfilesPendingRevocations', None)
        write_settings(path, current)


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
