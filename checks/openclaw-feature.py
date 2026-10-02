"""Measure the bundled plugin layout and the generated gateway configuration.

The assertions in checks/openclaw-feature.nix prove the Nix-side derivations. This file proves the
bytes: every catalogue plugin is physically inside the gateway closure as a bundled extension (the
only origin OpenClaw trusts for its trust-gated runtime surfaces), the generated configuration does
not fall back to a load path for them, and MCP Apps and Browser Control stay on distinct ports.
"""

import json
from pathlib import Path
import sys

gateway, ids, config_path, apps_offset, browser_control_offset = sys.argv[1:6]
gateway = Path(gateway)
ids = ids.split(",")
apps_offset = int(apps_offset)
browser_control_offset = int(browser_control_offset)

root = gateway / "lib" / "node_modules" / "openclaw"
for plugin_id in ids:
    manifest = root / "extensions" / plugin_id / "openclaw.plugin.json"
    code = root / "dist" / "extensions" / plugin_id
    assert manifest.is_file(), f"{plugin_id}: no discovery manifest at {manifest}"
    assert code.is_dir(), f"{plugin_id}: no bundled code at {code}"
    metadata = json.loads(manifest.read_text())
    assert metadata.get("id") == plugin_id, f"{plugin_id}: manifest id is {metadata.get('id')!r}"

config = json.loads(Path(config_path).read_text())
load_paths = config["plugins"].get("load", { }).get("paths", [ ])
# A catalogue plugin must be bundled, not load-path loaded: a load path carries no trusted install
# record, which is exactly what made `diffs` fail to register before.
leaked = [p for p in load_paths if "openclaw-runtime-plugin-" in p or "extensions/" in p]
assert not leaked, f"catalogue plugins must be bundled, not load-path loaded: {leaked}"

# MCP Apps derives from the gateway port; Browser Control is the next derived port. Both must be
# present and different, because the original collision was exactly these two being equal.
sandbox_port = config["mcp"]["apps"]["sandboxPort"]
gateway_port = config["gateway"]["port"]
assert sandbox_port == gateway_port + apps_offset, (gateway_port, sandbox_port)
assert sandbox_port != gateway_port + browser_control_offset, (
    "MCP Apps must not occupy the Browser Control port"
)

# A trusted-proxy browser is the only authentication path; the loopback proxy fallback must stay off.
assert config["gateway"]["auth"]["mode"] == "trusted-proxy"
assert config["gateway"]["auth"]["trustedProxy"]["allowLoopback"] is False
assert config["gateway"]["auth"]["trustedProxy"]["allowUsers"] == ["philipp"]

# The heartbeat has no messenger route in this deployment, so it must not claim one.
assert config["agents"]["defaults"]["heartbeat"]["target"] == "none"

# Research reads untrusted content; it must not be able to write or execute.
research = config["agents"]["entries"]["research"]
assert research["sandbox"]["workspaceAccess"] == "ro"
for denied in ("exec", "write", "apply_patch", "browser"):
    assert denied in research["tools"]["deny"], denied

# Session reach is a decision, not the Gateway-wide default.
assert config["tools"]["sessions"]["visibility"] == "agent"
assert config["tools"]["agentToAgent"]["enabled"] is True
assert config["tools"]["agentToAgent"]["allow"] == ["coding", "research", "operations"]

# Memory: the native backend is the active slot, and the two recall paths are explicitly on.
# `rememberAcrossConversations` is a per-agent product setting; it implies session indexing, so the
# global `sources` list must stay untouched and let OpenClaw derive it.
assert config["plugins"]["slots"]["memory"] == "memory-core"
assert config["memory"]["search"]["provider"] == "openai"
assert "sources" not in config["memory"]["search"], "sources must stay derived, not global"
assert config["agents"]["entries"]["main"]["memory"]["search"]["rememberAcrossConversations"] is True
for specialist in ("coding", "research", "operations"):
    assert "memory" not in config["agents"]["entries"][specialist], specialist

# Active Memory must be allowed as well as configured; a configured-but-not-allowed plugin is the
# exact warning the validator raises.
assert "active-memory" in config["plugins"]["allow"]
active = config["plugins"]["entries"]["active-memory"]
assert active["enabled"] is True
assert active["config"]["mode"] == "escalate"
assert active["config"]["agents"] == ["main"]
assert active["config"]["allowedChatTypes"] == ["direct"]
assert config["plugins"]["entries"]["memory-core"]["config"]["dreaming"]["enabled"] is True

# Node onboarding needs the bundled device-pair plugin; without it the native nodes cannot pair.
assert "device-pair" in config["plugins"]["allow"]
assert config["plugins"]["entries"]["device-pair"]["enabled"] is True

# Every catalogue plugin is named for activation. The Codex harness is part of that set because the
# GPT-5.4 fallback routes through it.
for plugin_id in ids:
    assert plugin_id in config["plugins"]["allow"], plugin_id
    assert config["plugins"]["entries"][plugin_id]["enabled"] is True, plugin_id

print("Expected bundled plugin layout, distinct MCP/Browser ports, narrowed specialisation and native memory: verified")
