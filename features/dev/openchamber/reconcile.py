"""Merge fleet-owned remote instances without replacing interactive settings or credentials."""

import json
import os
import secrets
from pathlib import Path
import sys
import tempfile


def reconcile(path, desired):
    current = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(current, dict):
        raise ValueError("OpenChamber settings must be a JSON object")
    original = json.dumps(current, sort_keys=True)
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
    default = current.get("desktopDefaultHostId", "")
    if default.startswith("nixfiles:") and default not in {item["id"] for item in desired["desktopHosts"]}:
        current["desktopDefaultHostId"] = "local"
    for key in ("desktopLocalPort", "desktopLanAccessEnabled"):
        if key in desired:
            current[key] = desired[key]
    current.setdefault("accountSwitchProviders", ["opencode-go"])
    if current.get("desktopLanAccessEnabled") and not current.get("desktopUiPassword"):
        current["desktopUiPassword"] = secrets.token_urlsafe(32)
    if path.exists() and json.dumps(current, sort_keys=True) == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=".nixfiles-")
    try:
        with os.fdopen(descriptor, "w") as handle:
            json.dump(current, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    reconcile(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()))
