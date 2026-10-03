// Exercise the pinned upstream plugin's actual advertisement gates without capturing media.
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const [gateway, ...args] = process.argv.slice(2);
const toolPath = args.pop();
const dist = `${gateway}/lib/node_modules/openclaw/dist`;
const runtimeFile = (await readdir(dist)).find((name) => /^bash-tools\.exec-runtime-.*\.mjs$/.test(name));
assert(runtimeFile, "Pinned exec runtime must be present");
const runtimeSource = await readFile(`${dist}/${runtimeFile}`, "utf8");
const resolveExport = runtimeSource.match(/resolveExecTarget as (\w+)/)?.[1];
assert(resolveExport, "Pinned exec target resolver must be exported");
const resolveExecTarget = (await import(pathToFileURL(`${dist}/${runtimeFile}`)))[resolveExport];
assert.equal(resolveExecTarget({ configuredTarget: "auto", sandboxAvailable: false }).effectiveHost, "gateway");
assert.equal(resolveExecTarget({ configuredTarget: "auto", requestedTarget: "node", sandboxAvailable: false }).effectiveHost, "node");
assert.throws(() => resolveExecTarget({ configuredTarget: "gateway", requestedTarget: "node", sandboxAvailable: false }), /exec host not allowed/);
assert.throws(() => resolveExecTarget({ configuredTarget: "auto", requestedTarget: "node", sandboxAvailable: true }), /exec host not allowed/);
console.log("Expected default gateway target, explicit node target and sandbox/fixed-host restrictions verified");
const { default: plugin } = await import(pathToFileURL(
  `${gateway}/lib/node_modules/openclaw/dist/extensions/linux-node/index.js`,
));

for (const configPath of args) {
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const commands = [];
  const policies = [];
  plugin.register({
    pluginConfig: config.plugins.entries["linux-node"].config,
    registerNodeHostCommand: (command) => commands.push(command),
    registerNodeInvokePolicy: (policy) => policies.push(policy),
  });
  const available = async (path) => {
    const advertised = [];
    for (const command of commands) {
      if (await command.isAvailable({ config, env: { PATH: path } })) {
        advertised.push(command.command);
      }
    }
    return advertised.sort();
  };
  assert.deepEqual(await available(toolPath), [
    "camera.clip", "camera.list", "camera.snap", "system.notify",
  ]);
  assert.deepEqual(await available(""), [], "Missing executables must remove capabilities");
  const disabled = structuredClone(config);
  disabled.plugins.entries["linux-node"].config.camera.enabled = false;
  for (const command of commands.filter((entry) => entry.command.startsWith("camera."))) {
    assert.equal(await command.isAvailable({ config: disabled, env: { PATH: toolPath } }), false);
  }
  assert(policies.some((policy) => policy.dangerous
    && policy.commands.includes("camera.snap") && policy.commands.includes("camera.clip")));
  console.log(`${configPath}: expected camera/notification advertisement, fail-closed gates and dangerous capture policy verified`);
}
