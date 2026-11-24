"""Fixture test for the Fleet runtime-extension installer.

The mock models only the API routes the installer calls. OpenChamber's own tests own the real HTTP
surface; this checks that the installer installs, approves, is idempotent and never prints secrets.
"""

import json
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

EXTENSION_ID = 'openchamber-fleet'
REQUESTED = ['opencodePlugin', 'service']
TOKEN = 'oc_client_test'
PASSWORD = 'test-password'


class State:
    installed = None
    requests = []

    def requested(self):
        return list(REQUESTED)

    def row(self):
        assert self.installed is not None
        return {
            'id': EXTENSION_ID,
            'version': self.installed['version'],
            'enabled': True,
            'capabilities': {
                'requested': self.requested(),
                'granted': list(self.installed['granted']),
            },
        }


class Handler(BaseHTTPRequestHandler):
    state: State

    def log_message(self, *_):
        return

    def send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self):
        length = int(self.headers.get('content-length') or 0)
        return json.loads(self.rfile.read(length) or b'{}')

    def authorized(self):
        return self.headers.get('authorization') == 'Bearer ' + TOKEN

    def do_GET(self):
        self.state.requests.append(('GET', self.path))
        if self.path == '/health':
            return self.send_json(200, {'runtime': 'web'})
        if self.path == '/api/guests':
            if not self.authorized():
                return self.send_json(401, {'error': 'unauthorized'})
            guests = [self.state.row()] if self.state.installed else []
            return self.send_json(200, {'guests': guests, 'opencodePlugins': {}})
        return self.send_json(404, {'error': 'not-found'})

    def do_POST(self):
        self.state.requests.append(('POST', self.path))
        if self.path == '/auth/session':
            body = self.read_json()
            if body.get('password') != PASSWORD:
                return self.send_json(401, {'error': 'Invalid credentials'})
            return self.send_json(200, {'authenticated': True, 'clientToken': TOKEN})
        if self.path == '/api/guests':
            if not self.authorized():
                return self.send_json(401, {'error': 'unauthorized'})
            body = self.read_json()
            path = body.get('path')
            if not path or not (Path(path) / 'package.json').is_file():
                return self.send_json(400, {'error': 'invalid-manifest'})
            version = json.loads((Path(path) / 'package.json').read_text())['version']
            self.state.installed = {'path': path, 'version': version, 'granted': []}
            return self.send_json(201, {'guest': self.state.row()})
        return self.send_json(404, {'error': 'not-found'})

    def do_PUT(self):
        self.state.requests.append(('PUT', self.path))
        if self.path != f'/api/guests/{EXTENSION_ID}/capabilities':
            return self.send_json(404, {'error': 'not-found'})
        if not self.authorized():
            return self.send_json(401, {'error': 'unauthorized'})
        if not self.state.installed:
            return self.send_json(404, {'error': 'not-found'})
        body = self.read_json()
        granted = body.get('granted')
        if sorted(granted or []) != sorted(self.state.requested()):
            return self.send_json(400, {'error': 'invalid-request'})
        self.state.installed['granted'] = list(granted)
        return self.send_json(200, {'guest': self.state.row()})


def run(installer, port, extension, password):
    return subprocess.run(
        [
            sys.executable,
            installer,
            '--mode', 'server',
            '--port', str(port),
            '--password-file', str(password),
            '--extension', str(extension),
            '--timeout', '5',
        ],
        capture_output=True,
        text=True,
        timeout=20,
    )


def main():
    installer = sys.argv[1]
    state = State()
    handler = type('Handler', (Handler,), {'state': state})
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    root = Path(tempfile.mkdtemp())
    extension = root / 'extension'
    extension.mkdir()
    (extension / 'package.json').write_text(json.dumps({
        'version': '0.4.0',
        'openchamber': {'id': EXTENSION_ID},
    }))
    password = root / 'password'
    password.write_text(PASSWORD + '\n', encoding='utf-8')

    try:
        first = run(installer, port, extension, password)
        if first.returncode != 0:
            print('installer requests:', state.requests, file=sys.stderr)
        if first.returncode != 0:
            raise AssertionError(f'first install failed: {first.stderr}')
        if state.installed is None:
            raise AssertionError('installer did not install the extension')
        if Path(state.installed['path']) != extension.resolve():
            raise AssertionError(f'wrong install path: {state.installed["path"]}')
        if sorted(state.installed['granted']) != sorted(REQUESTED):
            raise AssertionError(f'wrong grants: {state.installed["granted"]}')
        combined = first.stdout + first.stderr
        if TOKEN in combined or PASSWORD in combined:
            raise AssertionError('installer printed a credential')

        state.requests.clear()
        second = run(installer, port, extension, password)
        if second.returncode != 0:
            raise AssertionError(f'idempotent run failed: {second.stderr}')
        writes = [
            request for request in state.requests
            if request[0] != 'GET' and request[1] != '/auth/session'
        ]
        if writes:
            raise AssertionError(f'idempotent run wrote again: {writes}')

        (extension / 'package.json').write_text(json.dumps({
            'version': '0.4.1',
            'openchamber': {'id': EXTENSION_ID},
        }))
        state.requests.clear()
        third = run(installer, port, extension, password)
        if third.returncode != 0:
            raise AssertionError(f'update failed: {third.stderr}')
        if state.installed['version'] != '0.4.1':
            raise AssertionError(f'update did not install the new version: {state.installed["version"]}')
        if sorted(state.installed['granted']) != sorted(REQUESTED):
            raise AssertionError(f'update did not approve: {state.installed["granted"]}')

        # The desktop path uses the token the app writes into settings.json, without a password.
        state.installed = None
        settings = root / 'settings.json'
        settings.write_text(json.dumps({
            'desktopLocalPort': port,
            'desktopLocalClientToken': TOKEN,
        }), encoding='utf-8')
        desktop = subprocess.run(
            [
                sys.executable,
                installer,
                '--mode', 'desktop',
                '--settings-file', str(settings),
                '--extension', str(extension),
                '--timeout', '5',
            ],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if desktop.returncode != 0:
            raise AssertionError(f'desktop install failed: {desktop.stderr}')
        if state.installed is None:
            raise AssertionError('desktop installer did not install the extension')
        if sorted(state.installed['granted']) != sorted(REQUESTED):
            raise AssertionError(f'desktop install did not approve: {state.installed["granted"]}')
        if TOKEN in desktop.stdout + desktop.stderr:
            raise AssertionError('desktop installer printed the client token')

        # A desktop that is not up yet is a deferred retry, not a failed Home Manager unit.
        deferred = subprocess.run(
            [
                sys.executable,
                installer,
                '--mode', 'desktop',
                '--settings-file', str(root / 'not-running.json'),
                '--extension', str(extension),
                '--timeout', '1',
            ],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if deferred.returncode != 0:
            raise AssertionError(f'deferred desktop install failed: {deferred.stderr}')
        if 'not ready' not in deferred.stderr:
            raise AssertionError(f'deferred desktop install gave no reason: {deferred.stderr}')
    finally:
        server.shutdown()
        server.server_close()

    print('Fleet runtime-extension installer fixture passed')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except AssertionError as error:
        print(f'fleet installer test: {error}', file=sys.stderr)
        sys.exit(1)
