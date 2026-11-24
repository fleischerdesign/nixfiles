"""Mint an OpenChamber client token for a desktop that asks over SSH.

The server owns the UI password; the desktop never sees it. `openchamber-server-enroll --issue NAME`
prints one JSON object with a client token, which the desktop stores in its settings.
"""

import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

CACHE_PATH = Path(os.environ.get('HOME', '')) / '.local/state/openchamber/server-client-tokens.json'


def load_cache():
    try:
        return json.loads(CACHE_PATH.read_text())
    except Exception:
        return {}


def save_cache(value):
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    CACHE_PATH.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    CACHE_PATH.chmod(0o600)


def request(base, route, token=None, payload=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(
        base + route,
        headers=headers,
        data=json.dumps(payload).encode() if payload is not None else None,
        method='POST' if payload is not None else 'GET',
    )
    with http.open(req, timeout=5) as response:
        return json.load(response)


def password_from(path):
    value = Path(path).read_text().strip()
    if not value:
        raise ValueError('Empty server UI password')
    return value


def issue(port, password_path, source):
    base = 'http://127.0.0.1:' + str(port)
    if request(base, '/health').get('runtime') not in ('web', 'desktop'):
        raise ValueError('Server is not running')
    cache = load_cache()
    stored = cache.get(source)
    if stored:
        try:
            request(base, '/api/config/settings', stored)
            return {'clientToken': stored}
        except Exception:
            cache.pop(source, None)
    password = password_from(password_path)
    short = request(base, '/auth/session', payload={
        'password': password,
        'trustDevice': False,
        'issueClientToken': True,
        'clientLabel': 'nixfiles-enrollment',
        'clientKind': 'desktop-local',
        'dedupeKey': 'nixfiles-server-bootstrap',
    }).get('clientToken')
    if not short:
        raise ValueError('Server did not issue a bootstrap token')
    result = request(base, '/api/client-auth/clients', short, {
        'label': source,
        'clientKind': 'desktop',
        'dedupeKey': 'nixfiles-server:' + source,
    })
    token = result.get('token')
    if not token:
        raise ValueError('Server did not create a client token')
    cache[source] = token
    save_cache(cache)
    return {'clientToken': token}


if __name__ == '__main__':
    try:
        port = int(sys.argv[1])
        password_path = sys.argv[2]
        if len(sys.argv) == 5 and sys.argv[3] == '--issue':
            print(json.dumps(issue(port, password_path, sys.argv[4])))
        else:
            raise ValueError('usage: openchamber-server-enroll --issue NAME')
    except Exception as error:
        # A token or password must never enter the journal.
        print(f'OpenChamber server enrollment failed ({type(error).__name__})', file=sys.stderr)
        sys.exit(1)
