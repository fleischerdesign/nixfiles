"""Ask the built gateway binary whether it discovers and loads every catalogue plugin.

Reading the gateway filesystem back only repeats what the build wrote. The consumer-visible fact is
what `openclaw plugins list` reports: a plugin whose origin is not `bundled` (or whose install record
is not `trusted-official`) is refused the trust-gated runtime surfaces that `diffs` needs. Running the
real binary against the real generated config is the measurement at the level of the consumer.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary, config, ids = sys.argv[1:4]
ids = ids.split(",")

# A private state directory, as in the deployment: the gateway must never need to mutate the config.
with tempfile.TemporaryDirectory() as state:
    environment = {
        **os.environ,
        "HOME": state,
        "OPENCLAW_STATE_DIR": state,
        "OPENCLAW_CONFIG_PATH": config,
        "OPENCLAW_NIX_MODE": "1",
        "OPENCLAW_NO_AUTO_UPDATE": "1",
        "OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY": "1",
    }
    completed = subprocess.run(
        [binary, "plugins", "list", "--json"],
        env=environment,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"plugins list failed with exit {completed.returncode}")

    start = completed.stdout.find("{")
    if start < 0:
        print(completed.stdout, file=sys.stderr)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit("plugins list produced no JSON object")

plugins = {plugin["id"]: plugin for plugin in json.loads(completed.stdout[start:])["plugins"]}

for plugin_id in ids:
    plugin = plugins.get(plugin_id)
    assert plugin is not None, f"{plugin_id} is not discovered by the gateway at all"
    assert plugin.get("origin") == "bundled", f"{plugin_id}: origin is {plugin.get('origin')!r}"
    assert plugin.get("status") == "loaded", f"{plugin_id}: status is {plugin.get('status')!r}"
    reason = (plugin.get("trust") or {}).get("reason")
    assert reason == "bundled", f"{plugin_id}: trust reason is {reason!r}"

print(f"Expected the gateway to discover and load all {len(ids)} bundled plugins as trusted: verified")
