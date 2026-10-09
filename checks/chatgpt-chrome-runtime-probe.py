#!/usr/bin/env python3
"""Probe the ChatGPT Chrome native host the way the extension does.

The extension asks the host for its manifest (codexRuntime/hello) and then for a runtime
(codexRuntime/ensure). Both answers are checked here against the conditions the extension itself
applies, so a manifest the host would reject fails this check instead of surfacing as an opaque
error in the browser panel.
"""

import json
import os
import select
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REQUIRED_PROTOCOL_VERSION = 2


def request(proc, method, constraints, timeout=30):
    payload = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": {"constraints": constraints}}
    ).encode()
    proc.stdin.write(struct.pack("<I", len(payload)) + payload)
    proc.stdin.flush()
    readable, _, _ = select.select([proc.stdout], [], [], timeout)
    if not readable:
        raise SystemExit(f"{method}: no reply within {timeout}s")
    header = proc.stdout.read(4)
    if len(header) < 4:
        raise SystemExit(f"{method}: truncated reply")
    return json.loads(proc.stdout.read(struct.unpack("<I", header)[0]).decode())


def main(argv):
    host, manifest, extension_id = argv
    document = json.loads(Path(manifest).read_text())
    entry = document["entries"][0]
    with tempfile.TemporaryDirectory() as tmp:
        codex_home = Path(tmp) / "codex"
        codex_home.mkdir()
        # The host requires every path the entry names to exist. The real Codex home belongs to the
        # user, so the probe points the entry at its own temporary one.
        entry["paths"]["codexHome"] = str(codex_home)
        (codex_home / "chrome-native-hosts-v2.json").write_text(json.dumps(document, indent=2) + "\n")

        # The manifest is read from CODEX_HOME, so the probe writes it there and nothing else.
        env = {**os.environ, "CODEX_HOME": str(codex_home), "HOME": tmp}
        proc = subprocess.Popen(
            [host, f"chrome-extension://{extension_id}/"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        constraints = {
            "nativeHostName": entry["nativeHostNames"][0],
            "requiredNativeHostProtocolVersion": REQUIRED_PROTOCOL_VERSION,
            "requiredAppServerProtocolVersion": REQUIRED_PROTOCOL_VERSION,
            "extensionIds": [extension_id],
        }
        try:
            hello = request(proc, "codexRuntime/hello", constraints)["result"]
            print("hello:", json.dumps(hello, sort_keys=True))
            assert hello["manifestSchemaVersion"] == REQUIRED_PROTOCOL_VERSION, hello
            assert hello["nativeHostProtocolVersion"] == REQUIRED_PROTOCOL_VERSION, hello
            assert REQUIRED_PROTOCOL_VERSION in hello["supportedProtocolVersions"], hello

            reply = request(proc, "codexRuntime/ensure", constraints)
            if "result" not in reply:
                raise SystemExit(f"codexRuntime/ensure failed: {json.dumps(reply)[:600]}")
            ensure = reply["result"]
            print(
                "ensure:",
                json.dumps(
                    {
                        "entryId": ensure["entryId"],
                        "appServerProtocolVersion": ensure["selected"]["appServerProtocolVersion"],
                        "localAppServerUrl": ensure["localAppServerUrl"],
                    },
                    sort_keys=True,
                ),
            )
            assert ensure["selected"]["appServerProtocolVersion"] == REQUIRED_PROTOCOL_VERSION, ensure
            address = ensure["localAppServerUrl"]
            assert address.startswith("ws://127.0.0.1:"), address
            for key, value in ensure["runtimeConfig"].items():
                if key.endswith("Path"):
                    assert Path(value).exists(), f"{key} does not exist: {value}"
        finally:
            proc.terminate()
            stderr = proc.stderr.read().decode("utf-8", "replace")
            if stderr.strip():
                print("host stderr:", stderr.strip()[:500], file=sys.stderr)
    print("native host handshake and runtime: verified")


if __name__ == "__main__":
    main(sys.argv[1:])
