"""Merge fleet-owned remote instances without replacing interactive settings or credentials."""

import json
import os
from pathlib import Path
import sys
import tempfile


def reconcile(path, desired):
    current = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(current, dict):
        raise ValueError("OpenChamber settings must be a JSON object")
    for key in ("desktopSshInstances", "desktopHosts"):
        existing = current.get(key, [])
        if not isinstance(existing, list):
            raise ValueError(f"OpenChamber {key} must be a list")
        runtime = [item for item in existing if not item.get("id", "").startswith("nixfiles:")]
        by_id = {item["id"]: item for item in existing}
        # Preserve runtime-issued tokens, tunnel URLs and user auth fields for surviving peers.
        managed = []
        for item in desired[key]:
            previous = by_id.get(item["id"], {})
            merged = previous | item
            if key == "desktopHosts" and previous.get("url"):
                merged["url"] = previous["url"]
            managed.append(merged)
        current[key] = runtime + managed
    default = current.get("desktopDefaultHostId", "")
    if default.startswith("nixfiles:") and default not in {item["id"] for item in desired["desktopHosts"]}:
        current["desktopDefaultHostId"] = "local"
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
