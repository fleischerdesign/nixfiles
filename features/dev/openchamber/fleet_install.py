"""Install or update the Fleet runtime extension through the official OpenChamber API.

The extension is a normal folder install. This script only uses the local OpenChamber HTTP API:
the desktop app's client token, or a client token minted from the headless server's UI password.
It never writes OpenChamber's catalog itself.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

EXTENSION_ID = 'openchamber-fleet'
CLIENT_LABEL = 'nixfiles-fleet-extension'
CLIENT_DEDUPE = 'nixfiles-fleet-extension'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


class Retryable(Exception):
    """The local instance is not up yet; try again until the deadline."""


class ApiFailure(Exception):
    """The API answered and the answer is final."""

    def __init__(self, status, code, message):
        super().__init__(message)
        self.status = status
        self.code = code


def request(base, route, token=None, payload=None, method=None):
    headers = {'content-type': 'application/json'}
    if token:
        headers['authorization'] = 'Bearer ' + token
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        base + route,
        headers=headers,
        data=data,
        method=method or ('POST' if payload is not None else 'GET'),
    )
    try:
        with http.open(req, timeout=10) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        try:
            body = json.loads(error.read())
        except Exception:
            body = {}
        code = body.get('error') or body.get('message') or 'http-error'
        if isinstance(code, dict):
            code = code.get('code') or code.get('message') or 'http-error'
        raise ApiFailure(error.code, str(code), str(body.get('message') or code))
    except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as error:
        raise Retryable(str(error))


def health(base):
    try:
        result = request(base, '/health')
    except ApiFailure as error:
        if error.status >= 500:
            raise Retryable(f'OpenChamber health is not ready: {error.status} {error.code}')
        raise
    if result.get('runtime') not in ('web', 'desktop'):
        raise Retryable('OpenChamber has no ready runtime')


def password_from(path):
    if not path:
        return None
    try:
        value = Path(path).read_text(encoding='utf-8').strip()
    except FileNotFoundError:
        raise Retryable(f'OpenChamber password file does not exist yet: {path}')
    return value or None


def server_token(base, password_file):
    password = password_from(password_file)
    if not password:
        return None
    try:
        result = request(base, '/auth/session', payload={
            'password': password,
            'trustDevice': False,
            'issueClientToken': True,
            'clientLabel': CLIENT_LABEL,
            'clientKind': 'desktop-local',
            'dedupeKey': CLIENT_DEDUPE,
        })
    except ApiFailure as error:
        if error.status == 400 and 'password' in f'{error.code} {error}'.lower():
            return None
        raise
    token = result.get('clientToken')
    if not token:
        raise ApiFailure(500, 'no-client-token', 'OpenChamber did not issue a client token')
    return token


def desktop_connection(settings_file):
    path = Path(settings_file)
    try:
        settings = json.loads(path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        raise Retryable('OpenChamber desktop settings do not exist yet')
    except Exception as error:
        raise ApiFailure(400, 'settings-invalid', f'cannot read {path}: {error}')
    port = settings.get('desktopLocalPort')
    token = settings.get('desktopLocalClientToken')
    if not isinstance(port, int) or port <= 0:
        raise Retryable('OpenChamber desktop port is not ready')
    if not isinstance(token, str) or not token:
        raise Retryable('OpenChamber desktop client token is not ready')
    return f'http://127.0.0.1:{port}', token


def find_guest(guests, guest_id):
    return next((guest for guest in guests if guest.get('id') == guest_id), None)


def install(base, token, extension, version):
    """Install or replace the extension and approve exactly its requested grants."""
    catalog = request(base, '/api/guests', token).get('guests', [])
    row = find_guest(catalog, EXTENSION_ID)
    if row is None or row.get('version') != version:
        request(base, '/api/guests', token, {'path': str(extension), 'replace': True})
        catalog = request(base, '/api/guests', token).get('guests', [])
        row = find_guest(catalog, EXTENSION_ID)
    if row is None:
        raise ApiFailure(500, 'not-installed', f'{EXTENSION_ID} did not appear in the catalog')

    requested = row.get('capabilities', {}).get('requested', [])
    granted = row.get('capabilities', {}).get('granted', [])
    if sorted(requested) != sorted(granted):
        request(
            base,
            f'/api/guests/{EXTENSION_ID}/capabilities',
            token,
            {'granted': requested},
            method='PUT',
        )
        catalog = request(base, '/api/guests', token).get('guests', [])
        row = find_guest(catalog, EXTENSION_ID)
        if row is None:
            raise ApiFailure(500, 'not-installed', f'{EXTENSION_ID} vanished during approval')
        granted = row.get('capabilities', {}).get('granted', [])

    if sorted(row.get('capabilities', {}).get('requested', [])) != sorted(granted):
        raise ApiFailure(500, 'not-approved', f'{EXTENSION_ID} is still not fully approved')
    return row


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extension', required=True, help='absolute path to the extension package')
    parser.add_argument('--mode', choices=('server', 'desktop'), required=True)
    parser.add_argument('--port', type=int, help='headless OpenChamber port')
    parser.add_argument('--password-file', help='headless OpenChamber UI password file')
    parser.add_argument('--settings-file', help='desktop OpenChamber settings.json')
    parser.add_argument('--timeout', type=float, default=180.0, help='seconds to wait for the instance')
    return parser.parse_args()


def main():
    args = parse_args()
    extension = Path(args.extension)
    if not extension.is_absolute() or not extension.is_dir():
        raise ApiFailure(400, 'invalid-extension', f'{extension} is not an absolute directory')
    manifest = json.loads((extension / 'package.json').read_text(encoding='utf-8'))
    openchamber = manifest.get('openchamber') or {}
    if openchamber.get('id') != EXTENSION_ID:
        raise ApiFailure(400, 'invalid-extension', f'expected {EXTENSION_ID}, got {openchamber.get("id")!r}')
    version = manifest.get('version')
    if not isinstance(version, str) or not version:
        raise ApiFailure(400, 'invalid-extension', 'package.json has no version')

    settings_file = args.settings_file or str(Path.home() / '.config' / 'openchamber' / 'settings.json')
    deadline = time.monotonic() + args.timeout
    last = None
    while time.monotonic() < deadline:
        try:
            if args.mode == 'desktop':
                base, token = desktop_connection(settings_file)
            else:
                if not args.port:
                    raise ApiFailure(400, 'invalid-arguments', '--port is required in server mode')
                base = f'http://127.0.0.1:{args.port}'
                health(base)
                token = server_token(base, args.password_file)
            row = install(base, token, extension, version)
            print(f'{EXTENSION_ID} {row.get("version")}: installed and approved ({", ".join(row.get("capabilities", {}).get("granted", []))})')
            return 0
        except Retryable as error:
            last = error
            time.sleep(2)
        except ApiFailure as error:
            if error.status >= 500 or error.status == 429:
                last = error
                time.sleep(2)
                continue
            print(f'{EXTENSION_ID}: {error.status} {error.code}: {error}', file=sys.stderr)
            return 1
    print(f'{EXTENSION_ID}: OpenChamber is not available after {args.timeout:g}s: {last}', file=sys.stderr)
    return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except ApiFailure as error:
        print(f'{EXTENSION_ID}: {error.status} {error.code}: {error}', file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        # Never print a password or token; the exception text here cannot contain one.
        print(f'{EXTENSION_ID}: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
