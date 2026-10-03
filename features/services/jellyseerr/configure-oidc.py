"""Apply only owned OIDC settings through Seerr's native configuration API."""

import json
from pathlib import Path
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


def configure(base_url, settings_path, desired, secret, request=None):
    deadline = time.monotonic() + 90
    while True:
        try:
            settings = json.loads(Path(settings_path).read_text())
            break
        except FileNotFoundError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(2)
    api_key = settings["main"]["apiKey"]
    if not api_key or not secret:
        raise ValueError("Seerr configuration requires nonempty API and OIDC credentials")

    def native_request(method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = Request(base_url + path, data=data, method=method, headers={
            "X-Api-Key": api_key, "Content-Type": "application/json",
        })
        with urlopen(req, timeout=10) as response:
            return json.load(response)

    request = request or native_request
    while True:
        try:
            current = request("GET", "/api/v1/settings/oidc")
            break
        except HTTPError as error:
            if error.code not in (502, 503) or time.monotonic() >= deadline:
                raise
        except (URLError, TimeoutError):
            if time.monotonic() >= deadline:
                raise
        time.sleep(2)

    slug = desired["provider"]["slug"]
    owned = desired["provider"] | {"clientSecret": secret}
    providers = [p for p in current["providers"] if p["slug"] == slug]
    if len(providers) > 1:
        raise ValueError("Expected one Seerr OIDC provider per slug")
    existing = providers[0] if providers else {}
    if any(existing.get(key) != value for key, value in owned.items()):
        # The native PUT merges one provider; unrelated providers and UI-owned fields survive.
        # OpenAPI declares slug read-only: the path supplies it, never the request body.
        payload = {key: value for key, value in owned.items() if key != "slug"}
        if not providers:
            payload["newUserLogin"] = False
        request("PUT", "/api/v1/settings/oidc/" + quote(slug, safe=""), payload)
    if any(settings["main"].get(key) != value for key, value in desired["main"].items()):
        updated_main = request("POST", "/api/v1/settings/main", desired["main"])
        if any(updated_main.get(key) != value for key, value in desired["main"].items()):
            raise ValueError("Expected declared Seerr application URL and OIDC enablement")

    result = request("GET", "/api/v1/settings/oidc")
    updated = next(p for p in result["providers"] if p["slug"] == slug)
    if any(updated.get(key) != value for key, value in owned.items()):
        raise ValueError("Native Seerr OIDC configuration disagrees with the declared values")
    for provider in current["providers"]:
        after = next(p for p in result["providers"] if p["slug"] == provider["slug"])
        expected = provider | owned if provider["slug"] == slug else provider
        if after != expected:
            raise ValueError("Expected UI-owned OIDC fields and unrelated providers to be preserved")


if __name__ == "__main__":
    base_url, settings_path, desired_path, secret_path = sys.argv[1:]
    configure(base_url, settings_path, json.loads(Path(desired_path).read_text()),
              Path(secret_path).read_text().strip())
    print("Expected native OIDC settings and preserved UI-owned provider fields: verified")
