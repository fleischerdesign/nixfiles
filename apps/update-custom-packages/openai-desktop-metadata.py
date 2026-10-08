"""Resolve an immutable Linux artifact from OpenAI's published installer."""

import json
import re
import sys
from pathlib import Path


def release_metadata(installer: str, architecture: str) -> dict[str, str]:
    if architecture not in {"x86_64", "aarch64"}:
        raise ValueError(f"Unsupported OpenAI architecture: {architecture}")
    declarations = re.findall(r"^versions=\(([^\n)]+)\)$", installer, re.MULTILINE)
    if len(declarations) != 1:
        raise ValueError("Expected exactly one published OpenAI release list")
    versions = declarations[0].split()
    if not versions or any(not re.fullmatch(r"\d+\.\d+\.\d+", v) for v in versions):
        raise ValueError("Invalid published OpenAI release list")
    version = versions[0]
    return {
        "version": version,
        "url": (
            "https://persistent.oaistatic.com/codex-app-prod/linux/arch/"
            f"{version}/{architecture}/chatgpt-bin-{version}-1-{architecture}.pkg.tar.zst"
        ),
    }


if __name__ == "__main__":
    print(json.dumps(release_metadata(Path(sys.argv[1]).read_text(), sys.argv[2])))
