"""Merge fleet-owned remote instances without replacing interactive settings or credentials."""

from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile


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
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=".nixfiles-")
    try:
        with os.fdopen(descriptor, "w") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        Path(temporary).unlink(missing_ok=True)


def reconcile(path, desired):
    desired = dict(desired)
    with settings_lock(path):
        current = read_settings(path)
        if not isinstance(current, dict):
            raise ValueError("OpenChamber settings must be a JSON object")
        original = json.dumps(current, sort_keys=True)
        for key in ("desktopSshInstances", "desktopHosts"):
            if not isinstance(current.get(key, []), list):
                raise ValueError(f"OpenChamber {key} must be a list")
        desired_host_ids = {item["id"] for item in desired["desktopHosts"]}
        removed_hosts = [
            item for item in current.get("desktopHosts", [])
            if item.get("id", "").startswith("nixfiles:") and item["id"] not in desired_host_ids
        ]
        retired_ssh = {item["id"] for item in current.get("desktopSshInstances", [])
                       if item.get("id", "").startswith("nixfiles:")} if not desired["desktopSshInstances"] else set()
        for key in ("desktopSshInstances", "desktopHosts"):
            existing = current.get(key, [])
            if not isinstance(existing, list):
                raise ValueError(f"OpenChamber {key} must be a list")
            runtime = [item for item in existing if not item.get("id", "").startswith("nixfiles:")]
            by_id = {item["id"]: item for item in existing}
            # Preserve runtime tokens and auth fields; declared addresses replace old tunnels.
            managed = []
            for item in desired[key]:
                previous = by_id.get(item["id"], {})
                merged = previous | item
                if key == "desktopHosts" and item["id"] in retired_ssh:
                    merged.pop("clientToken", None)
                managed.append(merged)
            current[key] = runtime + managed
        if removed_hosts:
            pending = {
                item["id"]: item
                for item in current.get("nixfilesPendingRevocations", [])
                if isinstance(item, dict) and item.get("id")
            }
            for item in removed_hosts:
                if item.get("clientToken") and (item.get("apiUrl") or item.get("url")):
                    pending[item["id"]] = {
                        "id": item["id"],
                        "label": item.get("label", item["id"]),
                        "url": item.get("url"),
                        "apiUrl": item.get("apiUrl"),
                        "clientToken": item["clientToken"],
                    }
            if pending:
                current["nixfilesPendingRevocations"] = list(pending.values())
        default = current.get("desktopDefaultHostId", "")
        if "desktopDefaultHostId" in desired:
            current["desktopDefaultHostId"] = desired["desktopDefaultHostId"]
        elif default.startswith("nixfiles:") and default not in {item["id"] for item in desired["desktopHosts"]}:
            current["desktopDefaultHostId"] = "local"
        for key in ("desktopLocalPort", "desktopLanAccessEnabled"):
            if key in desired:
                current[key] = desired[key]
        current.setdefault("accountSwitchProviders", ["opencode-go"])
        ui_password_path = desired.pop("desktopUiPasswordPath", None)
        if ui_password_path:
            password = Path(ui_password_path).read_text().strip()
            if not password:
                raise ValueError("Empty OpenChamber UI password secret")
            current["desktopUiPassword"] = password
        elif current.get("desktopLanAccessEnabled") and not current.get("desktopUiPassword"):
            current["desktopUiPassword"] = secrets.token_urlsafe(32)
        if json.dumps(current, sort_keys=True) == original:
            return
        write_settings(path, current)


if __name__ == "__main__":
    reconcile(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()))
