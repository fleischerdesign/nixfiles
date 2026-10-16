"""Reconcile Nix-owned OpenChamber client grants using its authenticated API."""

import argparse
import fcntl
import http.cookiejar
import json
import os
from pathlib import Path
import socket
import tempfile
import urllib.error
import urllib.request

PREFIX = "nix-openchamber:"


class Pending(Exception):
    pass


class ApiError(Exception):
    def __init__(self, status):
        self.status = status
        super().__init__(f"OpenChamber API returned HTTP {status}")


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=".state-")
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Api:
    def __init__(self, url, password, timeout=5):
        self.url = url.rstrip("/")
        self.password = password
        self.timeout = timeout
        # Never send the password or bearer token through an HTTP redirect or proxy.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect(),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        )

    def request(self, route, method="GET", body=None, token=None):
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(self.url + route, data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Response bodies can contain credentials; do not put them in logs.
            status = error.code
            error.close()
            raise ApiError(status) from None
        except (urllib.error.URLError, TimeoutError, socket.timeout, ConnectionError):
            raise Pending("instance is unreachable") from None

    def login(self):
        result = self.request("/auth/session", "POST", {"password": self.password})
        if result.get("authenticated") is not True:
            raise RuntimeError("OpenChamber did not authenticate the management session")

    def valid(self, token):
        try:
            return self.request("/auth/session", token=token).get("authenticated") is True
        except ApiError as error:
            if error.status == 401:
                return False
            raise

    def revoke(self, client_id):
        try:
            self.request(f"/api/client-auth/clients/{client_id}", "DELETE")
        except ApiError as error:
            if error.status != 404:
                raise


def reconcile(manifest, state_path, password, timeout=5):
    state = read_json(state_path, {"version": 1, "connections": {}, "retired": {}})
    if state.get("version") != 1 or not isinstance(state.get("connections"), dict) or not isinstance(state.get("retired"), dict):
        raise ValueError("Invalid OpenChamber mesh state; refusing to replace it")
    desired = {host["name"]: host for host in manifest["hosts"]}
    results = {}
    errors = []

    def checkpoint():
        save(state_path, state)

    # Remove access from the desktop immediately, retaining enough information
    # to revoke the old grant once an offline target comes back.
    for name, entry in list(state["connections"].items()):
        if name not in desired or entry["url"] != desired[name]["url"]:
            state["retired"][entry["url"] + "#" + entry["clientId"]] = {"url": entry["url"], "clientId": entry["clientId"]}
            del state["connections"][name]
    checkpoint()

    def attempt(name, action):
        try:
            action()
            results[name] = "ready"
        except Pending:
            results[name] = "pending: instance unreachable"
        except Exception as error:
            # Only our own error classes have messages safe for a service log.
            message = str(error) if isinstance(error, ApiError) else type(error).__name__
            results[name] = f"error: {message}"
            errors.append(name)

    for key, entry in list(state["retired"].items()):
        def retire(entry=entry, key=key):
            api = Api(entry["url"], password, timeout)
            api.login()
            api.revoke(entry["clientId"])
            del state["retired"][key]
            checkpoint()
        attempt("retire:" + key.split("#")[0], retire)

    # Each target also removes obsolete Nix-owned incoming grants, including
    # grants whose original client's local state was lost. Phone pairings and
    # other manually issued tokens are outside this namespace.
    if manifest.get("server"):
        def prune():
            api = Api(manifest["server"]["url"], password, timeout)
            api.login()
            allowed = {PREFIX + name for name in manifest["server"]["clients"]}
            for client in api.request("/api/client-auth/clients")["clients"]:
                label = client.get("label", "")
                if client.get("clientKind") == "desktop" and label.startswith(PREFIX) and label not in allowed and not client.get("revokedAt"):
                    api.revoke(client["id"])
        attempt("incoming", prune)

    for name, host in desired.items():
        def ensure(name=name, host=host):
            api = Api(host["url"], password, timeout)
            previous = state["connections"].get(name)
            if previous and api.valid(previous["token"]):
                return
            api.login()
            result = api.request("/api/client-auth/clients", "POST", {
                "label": PREFIX + manifest["client"],
                "clientKind": "desktop",
                "dedupeKey": PREFIX + manifest["client"],
            })
            if not result.get("token") or not result.get("client", {}).get("id"):
                raise ValueError("Invalid client grant response")
            state["connections"][name] = {
                "url": host["url"], "token": result["token"], "clientId": result["client"]["id"],
            }
            checkpoint()
        attempt(name, ensure)
    state["status"] = results
    checkpoint()
    for name, result in results.items():
        print(f"{name}: {result}")
    return 1 if errors else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", action="store_true", help="Print reconciliation status without reading credentials")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("state", type=Path)
    parser.add_argument("password_file", type=Path)
    args = parser.parse_args()
    if args.status:
        state = read_json(args.state, {"status": {}})
        for name, status in state.get("status", {}).items():
            print(f"{name}: {status}")
        if not state.get("status"):
            print("No reconciliation has run yet.")
        return 0
    args.state.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(args.state.with_suffix(".lock"), "a", opener=lambda path, flags: os.open(path, flags, 0o600)) as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return reconcile(json.loads(args.manifest.read_text()), args.state, args.password_file.read_text().rstrip("\n"))


if __name__ == "__main__":
    raise SystemExit(main())
