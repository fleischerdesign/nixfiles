"""Reconcile declared Go API keys through OpenCode's credential API, without logging secrets."""

import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request


def reconcile(base, subscriptions):
    def request(method, route, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(
            base + route, data=data, method=method,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read()
            return json.loads(body) if body else None

    deadline = time.monotonic() + 60
    while True:
        try:
            integration = request("GET", "/api/integration/opencode")["data"]
            connections = integration.get("connections", [])
            active_id = connections[0].get("id") if connections else None
            stored = [item | {"active": item["id"] == active_id}
                      for item in connections if item["type"] == "credential"]
            break
        except (urllib.error.URLError, TimeoutError):
            if time.monotonic() >= deadline:
                raise RuntimeError("OpenChamber credential API did not become ready") from None
            time.sleep(1)
    existing = {item["id"]: item for item in stored}
    desired_ids = set()
    for subscription in subscriptions:
        value = {"type": "key", "key": Path(subscription["path"]).read_text().strip()}
        if not value["key"]:
            raise ValueError("OpenChamber received an empty Go credential")
        fingerprint = hashlib.sha256(value["key"].encode()).hexdigest()[:16]
        credential_id = "cred_nixfiles_go_" + subscription["name"] + "_" + fingerprint
        desired_ids.add(credential_id)
        previous = existing.get(credential_id)
        if previous:
            if previous["label"] != subscription["name"]:
                request("PATCH", "/api/credential/" + credential_id, {"label": subscription["name"]})
            continue
        # Install the replacement before deleting the old account. A failed create leaves it usable.
        old = next((item for item in stored if item["id"].startswith("cred_nixfiles_go_")
                    and item.get("label") == subscription["name"]), None)
        request("POST", "/api/credential", {
            "id": credential_id, "integrationID": "opencode",
            "label": subscription["name"], "value": value,
            "activate": old["active"] if old else False,
        })
    for credential_id in existing.keys() - desired_ids:
        if credential_id.startswith("cred_nixfiles_go_"):
            request("DELETE", "/api/credential/" + credential_id)

    # The supported settings API owns preferences.json and reloads the managed failover plugin.
    settings = request("GET", "/api/config/settings")
    providers = set(settings.get("accountSwitchProviders", []))
    if "opencode-go" not in providers:
        request("PUT", "/api/config/settings", {"accountSwitchProviders": sorted(providers | {"opencode-go"})})


if __name__ == "__main__":
    try:
        reconcile(sys.argv[1], json.loads(Path(sys.argv[2]).read_text()))
    except Exception as error:
        # HTTP responses and exception objects may contain credentials. Keep journal output bounded.
        status = f", HTTP {error.code}" if isinstance(error, urllib.error.HTTPError) else ""
        print(f"OpenChamber Go credential reconciliation failed ({type(error).__name__}{status})", file=sys.stderr)
        sys.exit(1)
