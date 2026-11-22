"""Merge the app-shipped extension registry with the declarative nixfiles plugins."""

import json
from pathlib import Path
import sys


def main(existing_path, ours_path):
    existing_file = Path(existing_path)
    existing = (
        json.loads(existing_file.read_text())
        if existing_file.exists()
        else {"version": 1, "extensions": []}
    )
    ours = json.loads(Path(ours_path).read_text())
    extensions = existing.setdefault("extensions", [])
    by_id = {item["id"]: item for item in extensions}
    by_directory = {item["directory"]: item for item in extensions}
    for item in ours.get("extensions", []):
        if item["id"] in by_id and by_id[item["id"]].get("directory") != item["directory"]:
            raise SystemExit(f"OpenChamber built-in extension ID collision: {item['id']}")
        if item["directory"] in by_directory and by_directory[item["directory"]]["id"] != item["id"]:
            raise SystemExit(f"OpenChamber built-in extension directory collision: {item['directory']}")
        by_id[item["id"]] = item
        by_directory[item["directory"]] = item
    existing["version"] = 1
    existing["extensions"] = list(by_id.values())
    existing_file.parent.mkdir(parents=True, exist_ok=True)
    existing_file.write_text(json.dumps(existing, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
