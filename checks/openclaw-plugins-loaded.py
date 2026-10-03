"""Require discovery and error-free runtime registration of official runtime plugins."""

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
    if completed.stderr:
        print(completed.stderr, file=sys.stderr)
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit(f"plugins list failed with exit {completed.returncode}")

    start = completed.stdout.find("{")
    if start < 0:
        print(completed.stdout, file=sys.stderr)
        print(completed.stderr, file=sys.stderr)
        raise SystemExit("plugins list produced no JSON object")

    for plugin_id in ids:
        inspection = subprocess.run(
            [binary, "plugins", "inspect", plugin_id, "--runtime", "--json"],
            env=environment, capture_output=True, text=True,
        )
        if inspection.stderr:
            print(inspection.stderr, file=sys.stderr)
        if inspection.returncode:
            print(inspection.stdout, file=sys.stderr)
            raise SystemExit(f"{plugin_id}: runtime inspection failed with exit {inspection.returncode}")
        runtime = json.loads(inspection.stdout[inspection.stdout.index("{"):])
        errors = [d for d in runtime.get("diagnostics", []) if d.get("level") == "error"]
        for diagnostic in runtime.get("diagnostics", []):
            print(json.dumps(diagnostic), file=sys.stderr)
        assert not errors, f"{plugin_id}: runtime registration failed: {errors}"

plugins = {plugin["id"]: plugin for plugin in json.loads(completed.stdout[start:])["plugins"]}

for plugin_id in ids:
    plugin = plugins.get(plugin_id)
    assert plugin is not None, f"{plugin_id} is not discovered by the gateway at all"
    assert plugin.get("status") == "loaded", f"{plugin_id}: status is {plugin.get('status')!r}"
    assert plugin.get("origin") == "config", f"{plugin_id}: expected official configured load path"
    # Loaded is insufficient: a missing host peer link can leave registered harnesses degraded.
    diagnostics = json.dumps(plugin).lower()
    assert "missing-openclaw-peer-link" not in diagnostics, f"{plugin_id}: host peer link is missing"

print(f"Expected the gateway to discover and load all {len(ids)} official runtime plugins: verified")
