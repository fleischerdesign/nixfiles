"""Copy the portable Fleet extension and reserve its Nix-built-in ID."""

import json
import shutil
import sys
from pathlib import Path


def main(source: str, destination: str) -> None:
    src = Path(source)
    dst = Path(destination)
    if not (src / "package.json").is_file():
        raise SystemExit("Fleet extension package.json is missing")
    shutil.copytree(src, dst)
    manifest_path = dst / "package.json"
    manifest = json.loads(manifest_path.read_text())
    openchamber = manifest.get("openchamber")
    if not isinstance(openchamber, dict):
        raise SystemExit("Fleet extension manifest has no openchamber block")
    openchamber["id"] = "openchamber-builtin-fleet"
    manifest_path.chmod(0o644)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare-fleet-extension.py <source> <destination>")
    main(sys.argv[1], sys.argv[2])
