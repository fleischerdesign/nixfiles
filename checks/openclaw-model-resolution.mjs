// Require every configured purpose-slot model to appear in the generated agent model catalog.
//
// The Gateway resolves an agent turn against its model registry, which is built from the generated
// plugin-owned catalog shards (and `models.json`). A provider's account-specific models reach that
// registry only through an authored `models.providers.*.models[]` row; the plugin manifest and the
// hosted-catalog overlay carry curated rows only. Removing the row silently drops the model from the
// registry, and the turn fails with `Unknown model`.
//
// `models list` renders a *different*, live catalog and passes even while every agent turn fails,
// so it cannot witness this. This measures the same generated artifact the registry loads, using the
// pinned Gateway's own planner, with discovery restricted to entry providers so it stays offline.
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [gateway, configPath] = process.argv.slice(2);
const dist = `${gateway}/lib/node_modules/openclaw/dist`;
process.env.OPENCLAW_NIX_MODE = "1";
const config = JSON.parse(await readFile(configPath, "utf8"));

const { n: planModelsJson } = await import(pathToFileURL(`${dist}/models-config-BsW-zGEK.mjs`));
const agentDir = await mkdtemp(join(tmpdir(), "openclaw-model-resolution-"));
const plan = await planModelsJson(config, agentDir, { providerDiscoveryEntriesOnly: true });

const inventory = new Map();
const ingest = (contents) => {
  for (const [provider, providerConfig] of Object.entries(JSON.parse(contents).providers ?? {})) {
    for (const model of providerConfig.models ?? []) inventory.set(`${provider}/${model.id}`, model);
  }
};
if (plan.modelsJsonContents) ingest(plan.modelsJsonContents);
for (const catalog of plan.pluginCatalogs ?? []) ingest(catalog.contents);

const defaults = config.agents.defaults;
const slots = {
  primary: defaults.model.primary,
  ...Object.fromEntries((defaults.model.fallbacks ?? []).map((ref, index) => [`fallback#${index + 1}`, ref])),
  utilityModel: defaults.utilityModel,
  "compaction.model": defaults.compaction.model,
  "compaction.memoryFlush.model": defaults.compaction.memoryFlush.model,
  "heartbeat.model": defaults.heartbeat.model,
  "subagents.model": defaults.subagents.model,
};
const unresolved = Object.fromEntries(Object.entries(slots).filter(([, ref]) => ref && !inventory.has(ref)));
assert.deepEqual(
  unresolved,
  {},
  `purpose slots missing from the generated agent model catalog: ${JSON.stringify(unresolved)}`,
);

// The transport is part of the contract: the Go endpoint rejects a Responses-only model sent as
// Completions, so Muse Spark must keep its override in the generated catalog too.
assert.equal(inventory.get("opencode-go/muse-spark-1.3-contributor").api, "openai-responses");
console.log(
  `Expected every configured purpose slot to appear in the generated agent model catalog: verified (${Object.keys(slots).length} slots)`,
);
