// Exact repair from openclaw/openclaw#194540, commit ee431f3f2dcd9cc04a86c5c7756d13f88bdf1dde.
// Remove this package and restore pkgs.openclaw-gateway in the Gateway feature
// when upstream ships the repair. Already-fixed inputs deliberately fail here.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const tag = "OpenClaw worker search-policy backport (#194540)";
const removal = "Remove packages/custom/openclaw-gateway-worker-fix and restore pkgs.openclaw-gateway in features/services/openclaw/gateway/nixos.nix.";
function fail(message) {
  throw new Error(`${tag}: ${message} ${removal}`);
}
const root = process.argv[2];
if (!root) fail("Pass the installed OpenClaw package root.");
const { parse } = createRequire(path.join(root, "package.json"))("acorn");
const dist = path.join(root, "dist");
const modules = fs.readdirSync(dist, { withFileTypes: true })
  .filter(entry => entry.isFile() && /\.m?js$/.test(entry.name))
  .map(entry => [entry.name, fs.readFileSync(path.join(dist, entry.name), "utf8")]);
function unique(marker) {
  const hits = modules.filter(([, source]) => source.includes(marker));
  if (hits.length !== 1) fail(`Expected one module containing ${marker}; found ${hits.length}. Inspect the new upstream layout.`);
  return hits[0];
}
const [readerName, reader] = unique("const executePreparedWorkerInference = async");
const [ownerName, owner] = unique("async function withPreparedSessionCapabilityRead(");
const syntax = source => parse(source, { ecmaVersion: "latest", sourceType: "module" });
function find(node, predicate, ancestors = [], hits = []) {
  if (!node || typeof node !== "object") return hits;
  if (predicate(node)) hits.push({ node, ancestors });
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) {
      for (const child of value) if (child?.type) find(child, predicate, [...ancestors, node], hits);
    } else if (value?.type) find(value, predicate, [...ancestors, node], hits);
  }
  return hits;
}
const ownerExports = find(syntax(owner), node => node.type === "ExportSpecifier" && node.local.name === "withPreparedSessionCapabilityRead");
if (ownerExports.length !== 1) fail("The capability preparation owner no longer has one named export.");
const exported = ownerExports[0].node.exported.name;
const tree = syntax(reader);
const targets = find(tree, node => node.type === "VariableDeclarator" && node.id.name === "executePreparedWorkerInference");
if (targets.length !== 1) fail("Worker inference entry point is ambiguous.");
const calls = find(targets[0].node.init, node => node.type === "CallExpression" && node.callee.name === "applyExtraParamsToAgent");
if (calls.length !== 1) fail("Expected exactly one worker stream-policy call.");
const { node: call, ancestors } = calls[0];
const preparers = tree.body.filter(node => node.type === "ImportDeclaration" && node.source.value === `./${ownerName}`)
  .flatMap(node => node.specifiers.filter(spec => spec.imported?.name === exported).map(spec => spec.local.name));
if (ancestors.some(node => node.type === "CallExpression" && preparers.includes(node.callee.name))) {
  fail("Upstream already prepares this policy read; this backport is obsolete.");
}
const prepareName = "__nixPrepareWorkerSearchPolicy";
const admittedName = "__nixAdmittedWorkerWebSearch";
if (reader.includes(prepareName) || reader.includes(admittedName)) fail("This package already carries the backport.");
if (ancestors.at(-1)?.type !== "ExpressionStatement" || call.arguments.length !== 12) {
  fail("Worker policy call shape changed; refusing to wrap an unfamiliar operation.");
}
const property = (object, name) => object?.type === "ObjectExpression"
  ? object.properties.find(prop => prop.type === "Property" && prop.key.name === name)?.value
  : undefined;
const context = property(call.arguments[11], "nativeWebSearchPolicyContext");
const search = property(context, "webSearchEnabled");
const sessionKey = property(context, "sessionKey");
const memberNamed = (node, name) => node?.type === "MemberExpression" && !node.computed
  && node.property.type === "Identifier" && node.property.name === name;
const chainValue = node => node?.type === "ChainExpression" ? node.expression : node;
const identifierName = node => node?.type === "Identifier" ? node.name : undefined;
const sameIdentifier = (left, right) => identifierName(left) !== undefined
  && identifierName(left) === identifierName(right);
// Minified npm builds rename every bound identifier, so verify the call shape
// upstream's repair depends on, not the source text that 2026.11.4 kept.
function admitsWorkerWebSearch(node) {
  if (node?.type !== "BinaryExpression" || node.operator !== "==="
      || node.right.type !== "Literal" || node.right.value !== true) return false;
  const someCall = chainValue(node.left);
  if (someCall?.type !== "CallExpression" || !memberNamed(someCall.callee, "some")
      || someCall.arguments.length !== 1) return false;
  const arrow = someCall.arguments[0];
  if (arrow?.type !== "ArrowFunctionExpression" || arrow.params.length !== 1
      || arrow.body?.type !== "BinaryExpression" || arrow.body.operator !== "==="
      || arrow.body.right.type !== "Literal" || arrow.body.right.value !== "web_search") return false;
  const pattern = arrow.params[0];
  if (pattern?.type !== "ObjectPattern" || pattern.properties.length !== 1) return false;
  const prop = pattern.properties[0];
  if (prop.type !== "Property" || prop.computed || prop.key.type !== "Identifier"
      || prop.key.name !== "definition" || prop.value.type !== "Identifier") return false;
  if (!memberNamed(arrow.body.left, "name") || !sameIdentifier(arrow.body.left.object, prop.value)) return false;
  const tools = someCall.callee.object;
  if (!memberNamed(tools, "tools") || tools.object?.type !== "AwaitExpression") return false;
  const surfaceCall = chainValue(tools.object.argument);
  if (surfaceCall?.type !== "CallExpression" || !memberNamed(surfaceCall.callee, "getSurface")
      || surfaceCall.arguments.length !== 1) return false;
  const lookup = surfaceCall.callee.object;
  if (lookup?.type !== "CallExpression" || identifierName(lookup.callee) !== "getWorkerTurnToolSurface"
      || lookup.arguments.length !== 1) return false;
  return sameIdentifier(lookup.arguments[0], surfaceCall.arguments[0]);
}
// The admitted session key stays the worker target's: the same object supplies
// the agent id on this call.
function readsTargetSessionKey(node) {
  if (!memberNamed(node, "sessionKey") || node.object.type !== "Identifier") return false;
  return call.arguments.some(argument => memberNamed(argument, "agentId")
    && identifierName(argument.object) === node.object.name);
}
if (!search || !sessionKey || !admitsWorkerWebSearch(search) || !readsTargetSessionKey(sessionKey)) {
  fail("Admitted web-search policy input changed; inspect upstream rather than guessing.");
}

// Keep the asynchronous tool-surface lookup OUTSIDE the synchronous preparation
// callback. Wrapping an async callback does not catch the capability-read retry.
const admitted = reader.slice(search.start, search.end);
const syncCall = reader.slice(call.start, search.start) + admittedName + reader.slice(search.end, call.end);
const syncTree = syntax(`const check = () => ${syncCall};`);
if (find(syncTree, node => node.type === "AwaitExpression").length) fail("The policy callback would still contain an asynchronous operation.");
const indentation = reader.slice(reader.lastIndexOf("\n", call.start) + 1, call.start);
const replacement = `const ${admittedName} = ${admitted};\n${indentation}await ${prepareName}(() => ${syncCall})`;
const patched = `import { ${exported} as ${prepareName} } from "./${ownerName}";\n`
  + reader.slice(0, call.start) + replacement + reader.slice(call.end);
syntax(patched); // Validate the complete artifact before changing any bytes.
fs.writeFileSync(path.join(dist, readerName), patched);
console.log(`${tag}: ${readerName} now prepares the synchronous policy read; tool admission is unchanged.`);
