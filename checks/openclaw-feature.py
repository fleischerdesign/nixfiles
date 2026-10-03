"""Measure official runtime-plugin payloads and generated gateway configuration."""

import json
from pathlib import Path
import subprocess
import sys

gateway, ids, config_path, apps_offset, browser_control_offset = sys.argv[1:6]
gateway = Path(gateway)
ids = ids.split(",")
apps_offset = int(apps_offset)
browser_control_offset = int(browser_control_offset)

root = gateway / "lib" / "node_modules" / "openclaw"
config = json.loads(Path(config_path).read_text())
load_paths = config["plugins"].get("load", {}).get("paths", [])
plugin_roots = {json.loads((Path(p) / "openclaw.plugin.json").read_text())["id"]: Path(p)
                for p in load_paths}
for plugin_id in ids:
    assert plugin_id in plugin_roots, f"{plugin_id}: missing official load path"
    code = plugin_roots[plugin_id]
    manifest = code / "openclaw.plugin.json"
    assert manifest.is_file(), f"{plugin_id}: no discovery manifest at {manifest}"
    assert code.is_dir(), f"{plugin_id}: no bundled code at {code}"
    metadata = json.loads(manifest.read_text())
    assert metadata.get("id") == plugin_id, f"{plugin_id}: manifest id is {metadata.get('id')!r}"
    package = json.loads((code / "package.json").read_text())
    for entry in package["openclaw"].get("runtimeExtensions", package["openclaw"]["extensions"]):
        assert (code / entry).is_file(), f"{plugin_id}: declared extension entry is absent: {entry}"
    if "openclaw" in package.get("peerDependencies", {}):
        peer = code / "node_modules" / "openclaw"
        assert peer.is_symlink(), f"{plugin_id}: missing explicit host peer link"
        assert (peer / "package.json").is_file(), f"{plugin_id}: broken OpenClaw peer"

# Verify only installation records actually authored in the configuration. Official load paths are
# not npm installations; inventing npm records subjects them to an unrelated installer boundary.
payload_modules = [p for p in (root / "dist").glob("payload-verification-*.mjs")
                   if "runPluginPayloadSmokeCheck as r" in p.read_text()]
assert len(payload_modules) == 1, "Expected one upstream payload validator"
records = config["plugins"].get("installs", {})
subprocess.run([
    "node", "--input-type=module", "-e",
    'const {r: check} = await import(process.argv[1]); '
    'const verdict = await check({records: JSON.parse(process.argv[2])}); '
    'if (verdict.failures.length) { console.error(JSON.stringify(verdict)); process.exit(1); }',
    payload_modules[0].as_uri(), json.dumps(records),
], check=True)

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

# One personal agent, with a stable id for existing conversations and memory.
assert set(config["agents"]["entries"]) == {"main"}
main = config["agents"]["entries"]["main"]
assert main["name"] == "Moebius"
assert main["identity"]["name"] == "Moebius"
assert main["subagents"]["allowAgents"] == ["main"]
assert config["agents"]["defaults"]["systemAgent"]["agentId"] == "main"

# Purpose routes must not inherit the main model accidentally or enable API-billed chat fallback.
defaults = config["agents"]["defaults"]
free = "opencode-go/space-bunny-free"
worker = "opencode-go/deepseek-v4.1-flash"
assert defaults["model"] == {
    "primary": "openai/gpt-6.1-sol",
    "fallbacks": [worker, "opencode-go/mimo-v2.6-flash"],
}
assert config["models"]["providers"]["openai"]["auth"] == "oauth"
assert "apiKey" not in config["models"]["providers"]["openai"]
assert config["models"]["providers"]["openai"]["models"][0]["api"] == "openai-chatgpt-responses"
assert "agentRuntime" not in defaults["models"].get("openai/gpt-6.1-sol", {})
assert defaults["subagents"]["model"] == worker
assert defaults["heartbeat"]["model"] == worker
assert defaults["utilityModel"] == free
assert defaults["compaction"]["model"] == free
assert defaults["compaction"]["memoryFlush"]["model"] == free
assert config["memory"]["search"]["model"] == "text-embedding-3-small"
assert config["memory"]["search"]["remote"]["apiKey"]["id"] == "OPENAI_API_KEY"

# Session reach is a decision, not the Gateway-wide default.
assert config["tools"]["sessions"]["visibility"] == "agent"
assert config["tools"]["agentToAgent"]["enabled"] is False
assert config["tools"]["agentToAgent"]["allow"] == []
assert config["tools"]["exec"]["host"] == "auto", "Explicit node execution must not be locked to gateway"

# Memory: the native backend is the active slot, and the two recall paths are explicitly on.
# `rememberAcrossConversations` is a per-agent product setting; it implies session indexing, so the
# global `sources` list must stay untouched and let OpenClaw derive it.
assert config["plugins"]["slots"]["memory"] == "memory-core"
assert config["memory"]["search"]["provider"] == "openai"
assert "sources" not in config["memory"]["search"], "sources must stay derived, not global"
assert config["agents"]["entries"]["main"]["memory"]["search"]["rememberAcrossConversations"] is True

# Active Memory must be allowed as well as configured; a configured-but-not-allowed plugin is the
# exact warning the validator raises.
assert "active-memory" in config["plugins"]["allow"]
active = config["plugins"]["entries"]["active-memory"]
assert active["enabled"] is True
assert active["config"]["mode"] == "escalate"
assert active["config"]["agents"] == ["main"]
assert active["config"]["allowedChatTypes"] == ["direct"]
assert active["config"]["model"] == free
assert config["plugins"]["entries"]["memory-core"]["config"]["dreaming"]["enabled"] is True
memory_core = config["plugins"]["entries"]["memory-core"]
assert memory_core["config"]["dreaming"]["model"] == free
assert memory_core["subagent"] == {"allowModelOverride": True, "allowedModels": [free]}
assert config["plugins"]["entries"]["llm-task"]["config"] == {
    "defaultProvider": "opencode-go", "defaultModel": "space-bunny-free",
}

# Node onboarding needs the bundled device-pair plugin; without it the native nodes cannot pair.
assert "device-pair" in config["plugins"]["allow"]
assert config["plugins"]["entries"]["device-pair"]["enabled"] is True

# Linux node policies also run on the gateway; local capture remains opt-in on the node.
assert "linux-node" in config["plugins"]["allow"]
assert config["plugins"]["entries"]["linux-node"]["enabled"] is True
assert config["gateway"]["nodes"]["commands"]["allow"] == ["camera.snap", "camera.clip"]

# Every catalogue plugin is named for activation. The Codex harness is part of that set because the
# subscription-backed main model routes through it.
for plugin_id in ids:
    assert plugin_id in config["plugins"]["allow"], plugin_id
    assert config["plugins"]["entries"][plugin_id]["enabled"] is True, plugin_id

print("Expected official plugin payloads, distinct MCP/Browser ports, one Moebius agent and native memory: verified")
