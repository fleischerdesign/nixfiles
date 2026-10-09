#!/usr/bin/env python3
"""Write the Codex Chrome runtime manifest the desktop app registers.

The desktop app publishes its app-server for the Chrome extension in chrome-native-hosts-v2.json
(schema version 2). It does that while installing its bundled Chrome plugin, a step that never
completes under this packaging, so this reproduces the file from the same inputs the app uses: the
host name and the extension ids come from the app's extension-ids.json, the paths from the app
bundle, and the two identifiers are sha256 over the app's own field order, hex, first 32
characters.

The app also writes presence and update timestamps. Both are optional in its schema and the native
host accepts entries without them - a package that does not run cannot report a process id or a
last-seen time, and inventing either would be worse than leaving them out.
"""

import hashlib
import json
import sys
from pathlib import Path

SCHEMA_VERSION = 2
PROTOCOL_VERSION = 2


def identifier(prefix, parts):
    digest = hashlib.sha256()
    for part in parts:
        digest.update(part.encode())
        digest.update(b"\0")
    return prefix + digest.hexdigest()[:32]


def channel_for(host_name):
    if host_name.endswith(".dev"):
        return "dev"
    if host_name.endswith(".internal"):
        return "internal"
    return "prod"


def main(argv):
    if len(argv) < 8:
        raise SystemExit(
            "usage: write-runtime-manifest.py <out-dir> <host-name> <version> <extension-host> "
            "<resources-path> <codex-home> <plugin-dir> <extension-id>..."
        )
    out_dir, host_name, version, extension_host, resources, codex_home, plugin, *extension_ids = argv

    channel = channel_for(host_name)
    paths = {
        "browserClientPath": f"{plugin}/scripts/browser-client.mjs",
        "browserServicePath": f"{plugin}/scripts/browser-service.mjs",
        "codexCliPath": f"{resources}/codex",
        "codexHome": codex_home,
        "extensionHostPath": extension_host,
        "nodePath": f"{resources}/cua_node/bin/node",
        "nodeReplPath": f"{resources}/cua_node/bin/node_repl",
        "resourcesPath": resources,
    }
    entry = {
        "schemaVersion": SCHEMA_VERSION,
        "appServerProtocolVersion": PROTOCOL_VERSION,
        "appVersion": version,
        "channel": channel,
        "cliVersion": version,
        "entryId": identifier(
            "codex-runtime-",
            [
                host_name,
                *extension_ids,
                channel,
                version,
                paths["extensionHostPath"],
                paths["codexCliPath"],
                paths["codexHome"],
                paths["resourcesPath"],
            ],
        ),
        "extensionBuildChannels": [channel, "prod"] if channel == "internal" else [channel],
        "extensionIds": list(extension_ids),
        "installId": identifier("codex-install-", [host_name, paths["resourcesPath"], codex_home]),
        "nativeHostNames": [host_name],
        "nativeHostProtocolVersion": PROTOCOL_VERSION,
        "nativeHostVersion": version,
        "paths": paths,
        "proxyHost": "127.0.0.1",
        "proxyPort": 0,
    }

    target = Path(out_dir) / "share" / "codex-runtime-manifest" / "chrome-native-hosts-v2.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"schemaVersion": SCHEMA_VERSION, "entries": [entry]}, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
