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
pairing_url = config["plugins"]["entries"]["device-pair"]["config"]["publicUrl"]
assert pairing_url == config["gateway"]["publicOrigin"].replace("https://", "wss://", 1)
setup_modules = [p for p in (root / "dist").glob("setup-code-*.mjs")
                 if "resolvePairingSetupFromConfig as a" in p.read_text()]
assert len(setup_modules) == 1, "Expected one native pairing setup resolver"
# Measure full-access setup generation without minting a real token or requiring network access.
subprocess.run([
    "node", "--input-type=module", "-e",
    '''const {a: resolve, r: publicUrl} = await import(process.argv[1]);
    const cfg = JSON.parse(process.argv[2]);
    const options = {publicUrl: publicUrl(cfg),
      env: {...process.env, OPENCLAW_GATEWAY_PASSWORD: "synthetic"},
      issuedBootstrap: {token: "synthetic", setupId: "fixture", expiresAtMs: Date.now() + 60000}};
    const secure = await resolve(cfg, options);
    if (!secure.ok || secure.access !== "full" || secure.accessDowngraded ||
        secure.payload.url !== cfg.plugins.entries["device-pair"].config.publicUrl)
      throw new Error("Expected contract-derived TLS pairing with full access");
    const insecure = await resolve(cfg, {...options, publicUrl: "ws://192.168.0.2:18789"});
    if (!insecure.ok || insecure.access !== "limited" || !insecure.accessDowngraded)
      throw new Error("Expected cleartext private-network pairing to retain its access restriction");''',
    setup_modules[0].as_uri(), json.dumps(config),
], check=True)
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
free = "opencode-go/longcat-2.5-preview-free"
worker = "opencode-go/deepseek-v4.1-flash"
main = "opencode-go/muse-spark-1.3-contributor"
assert defaults["model"] == {
    "primary": main,
    "fallbacks": [worker, "opencode-go/mimo-v2.6-flash"],
}
assert config["models"]["providers"]["openai"]["auth"] == "oauth"
assert "apiKey" not in config["models"]["providers"]["openai"]
assert config["models"]["providers"]["openai"]["models"][0]["api"] == "openai-chatgpt-responses"
# The OpenAI ChatGPT route is declared and selectable but is no longer any purpose slot's primary;
# the main binding now lives on the Go provider, so this declaration must not track it.
assert config["models"]["providers"]["openai"]["models"][0]["id"] == "gpt-6.1-sol"
sol = config["models"]["providers"]["openai"]["models"][0]
assert sol["contextWindow"] == 872000, "Expected OAuth capacity, not the Platform API window"
assert sol["contextTokens"] == 272000, "Expected the OAuth catalogue's default runtime budget"
assert defaults["models"]["openai/*"]["agentRuntime"] == {"id": "openclaw"}
# Exercise native runtime selection and placement projection, not only the authored configuration.
runtime_modules = [p for p in (root / "dist").glob("thinking-runtime-*.mjs")
                   if "resolveEffectiveAgentRuntime as o" in p.read_text()]
placement_modules = [p for p in (root / "dist").glob("placement-session-runtime-*.mjs")
                     if "projectWorkerPlacementAgentRuntime as t" in p.read_text()]
assert len(runtime_modules) == 1, "Expected one native runtime resolver"
assert len(placement_modules) == 1, "Expected one native placement projector"
subprocess.run([
    "node", "--input-type=module", "-e",
    '''const {o: resolve} = await import(process.argv[1]);
    const {t: project} = await import(process.argv[2]);
    const cfg = JSON.parse(process.argv[3]);
    for (const modelId of ["gpt-6.1-sol", "gpt-5.5"]) {
      const id = resolve({cfg, provider: "openai", modelId, agentId: "main"});
      const runtime = project({id, source: "model"});
      if (id !== "openclaw" || !runtime.devicePlacementSupported ||
          runtime.cloudPlacementExecutionMode !== "worker-turn" ||
          !runtime.devicePlacement?.consumesWorkerSlot)
        throw new Error(`Expected native OpenAI device placement: ${JSON.stringify(runtime)}`);
    }''',
    runtime_modules[0].as_uri(), placement_modules[0].as_uri(), json.dumps(config),
], check=True)
assert defaults["subagents"]["model"] == worker
assert defaults["heartbeat"]["model"] == worker
assert defaults["utilityModel"] == free
assert defaults["compaction"]["model"] == free
assert defaults["compaction"]["memoryFlush"]["model"] == free

# The Go provider exposes each published route exactly once: a second registration of one model id
# with different metadata is how a purpose slot and its billing class drift apart.
go_provider = config["models"]["providers"]["opencode-go"]
assert go_provider["baseUrl"] == "https://opencode.ai/zen/go/v1"
go_ids = [m["id"] for m in go_provider["models"]]
assert len(go_ids) == len(set(go_ids)), f"duplicate opencode-go model ids: {go_ids}"
assert set(go_ids) == {main.removeprefix("opencode-go/"), "longcat-2.5-preview-free", "deepseek-v4.1-flash", "mimo-v2.6-flash"}, go_ids
main_model = next(m for m in go_provider["models"] if m["id"] == "muse-spark-1.3-contributor")
# Published Muse Spark 1.3 Contributor limits and Go pricing: 1,048,576 context / 131,072 output.
assert main_model["contextWindow"] == 1048576
assert main_model["maxTokens"] == 131072
assert main_model["cost"] == {"input": 0.1, "output": 0.2, "cacheRead": 0.002, "cacheWrite": 0}
assert main_model["reasoning"] is True and main_model["input"] == ["text", "image"]
free_model = next(m for m in go_provider["models"] if m["id"] == "longcat-2.5-preview-free")
# Published LongCat limits: 1,000,000 context, 131,072 output. maxTokens is the output cap and must
# not be turned into an artificial context budget, so no contextTokens is authored for this route.
assert free_model["contextWindow"] == 1000000
assert free_model["maxTokens"] == 131072
assert "contextTokens" not in free_model, "maxTokens must not be re-cast as a context budget"
assert free_model["cost"] == {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
assert free_model["reasoning"] is True and free_model["input"] == ["text", "image"]
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
    "defaultProvider": "opencode-go", "defaultModel": "longcat-2.5-preview-free",
}

# Node onboarding needs the bundled device-pair plugin; without it the native nodes cannot pair.
assert "device-pair" in config["plugins"]["allow"]
assert config["plugins"]["entries"]["device-pair"]["enabled"] is True

# Linux node policies also run on the gateway; local capture remains opt-in on the node.
assert "linux-node" in config["plugins"]["allow"]
assert config["plugins"]["entries"]["linux-node"]["enabled"] is True
assert config["gateway"]["nodes"]["commands"]["allow"] == ["camera.snap", "camera.clip"]

# Every selected official runtime plugin is named for activation.
for plugin_id in ids:
    assert plugin_id in config["plugins"]["allow"], plugin_id
    assert config["plugins"]["entries"][plugin_id]["enabled"] is True, plugin_id

print("Expected official plugin payloads, distinct MCP/Browser ports, one Moebius agent and native memory: verified")
