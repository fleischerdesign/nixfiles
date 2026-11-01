// Regression proof for the repository-session spawn refusal.
//
// A worker session created from a repository keeps its checkout on the paired
// node. A subagent spawn forces a managed worktree; before the patch the Gateway
// inherited nothing, fell back to the agent workspace and ran
// `git ls-remote origin` in an unrelated repository. This builds nothing itself:
// it loads the real patched chunk, stubs only the session-entry read that the
// guard performs, and proves the refusal happens before any workspace is
// resolved. Project, worktree and plain parents keep upstream resolution.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { register } from "node:module";
import { pathToFileURL } from "node:url";

const [gateway] = process.argv.slice(2);
if (!gateway) {
  console.error("usage: openclaw-node-spawn-source.mjs <gateway-store-path>");
  process.exit(2);
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}
function pass(message) {
  console.log(`PASS: ${message}`);
}

const dist = path.join(gateway, "lib/node_modules/openclaw/dist");
if (!fs.existsSync(dist)) fail(`dist missing: ${dist}`);

const marker = "async function prepareSessionWorktreeCreation(";
const anchor = "const inheritedSource = params.inheritParentKey";
const owners = fs
  .readdirSync(dist, { withFileTypes: true })
  .filter((entry) => (entry.isFile() || entry.isSymbolicLink()) && /\.m?js$/.test(entry.name))
  .filter((entry) => {
    const source = fs.readFileSync(path.join(dist, entry.name), "utf8");
    return source.includes(marker) && source.includes(anchor);
  });
if (owners.length !== 1) fail(`expected one spawn preparation chunk, found ${owners.length}`);

const chunk = path.join(dist, owners[0].name);
const source = fs.readFileSync(chunk, "utf8");
const functionIndex = source.indexOf(marker);
const guardIndex = source.indexOf("__ocNodeSpawnSourcePolicy(parent.entry)");
const inheritIndex = source.indexOf(anchor);
const fallbackIndex = source.indexOf("resolveAgentWorkspaceDir(cfg, lifecycleTarget.agentId)");

assert.match(
  source,
  /import \{ parentSpawnSourceRefusal as __ocNodeSpawnSourcePolicy \} from "\.\/nix-node-spawn-source-policy\.mjs";/,
  "spawn source policy is not imported by the built chunk",
);
if (!(functionIndex >= 0 && functionIndex < guardIndex)) {
  fail("the refusal is not inside prepareSessionWorktreeCreation");
}
if (!(guardIndex < inheritIndex)) {
  fail("the refusal runs after the inherited source is resolved");
}
if (!(fallbackIndex > inheritIndex)) {
  fail("the agent-workspace fallback is missing or moved before inheritance");
}
if (!/if \(refusal\) return err\(errorShape\(ErrorCodes\.UNAVAILABLE, refusal\)\);/.test(source)) {
  fail("the refusal does not return a typed UNAVAILABLE result");
}
pass("built chunk refuses a repository-only parent before resolving a workspace");

const policyPath = path.join(dist, "nix-node-spawn-source-policy.mjs");
if (!fs.existsSync(policyPath)) fail(`installed policy missing: ${policyPath}`);
const { parentSpawnSourceRefusal } = await import(pathToFileURL(policyPath));

const repositoryParent = { repositoryWorkspaceId: "1958311a-a758-4d52-9233-c615cecd480e" };
const refusal = parentSpawnSourceRefusal(repositoryParent);
assert.equal(typeof refusal, "string");
assert.match(refusal, /paired node/);
assert.match(refusal, /Gateway project/);
pass("repository-only parent is refused with an actionable message");

const unchanged = [
  ["project parent", { projectId: "nixfiles", repositoryWorkspaceId: "workspace-id" }],
  ["managed worktree parent", { worktree: { id: "wt-1" }, repositoryWorkspaceId: "workspace-id" }],
  ["pending worktree parent", { pendingWorktree: { workspace: "/tmp/x" }, repositoryWorkspaceId: "w" }],
  ["project-only parent", { projectId: "nixfiles" }],
  ["plain workspace parent", {}],
  ["blank repository id", { repositoryWorkspaceId: "   " }],
  ["no parent entry", undefined],
];
for (const [label, entry] of unchanged) {
  assert.equal(parentSpawnSourceRefusal(entry), undefined, `${label} must keep upstream resolution`);
}
pass(`${unchanged.length} project, worktree and plain-parent cases keep upstream resolution`);

// Execute the real function. The only double is the session-entry read the guard
// performs; everything else is the shipped chunk.
const hooksFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "spawn-source-")), "hooks.mjs");
fs.writeFileSync(
  hooksFile,
  `export async function resolve(specifier, context, next) {
  if (context.parentURL?.includes("session-worktree-preparation") && specifier.includes("session-utils-store")) {
    return {
      url: "data:text/javascript,export const i = () => ({ entry: globalThis.__ocParentEntry });",
      format: "module",
      shortCircuit: true,
    };
  }
  return next(specifier, context);
}
`,
);
register(pathToFileURL(hooksFile));

const chunkModule = await import(pathToFileURL(chunk));
const prepareSessionWorktreeCreation = Object.values(chunkModule).find(
  (value) => typeof value === "function" && value.name === "prepareSessionWorktreeCreation",
);
if (!prepareSessionWorktreeCreation) fail("prepareSessionWorktreeCreation is not exported by the built chunk");

const call = (parentEntry) =>
  prepareSessionWorktreeCreation({
    cfg: { agents: { defaults: { workspace: path.join(os.tmpdir(), "missing-workspace") } }, sessions: {} },
    target: { agentId: "main", key: "agent:main:subagent:probe", storePath: "/nonexistent/store" },
    inheritParentKey: "agent:main:dashboard:probe-parent",
    deferWorktree: true,
    label: "probe",
    titleSource: "probe",
    runSetupScript: false,
    commitGuard: () => {},
  });

globalThis.__ocParentEntry = repositoryParent;
const refused = await call(repositoryParent);
assert.equal(refused.ok, false, "a repository-only parent must not resolve a worktree");
assert.equal(refused.error.code, "UNAVAILABLE");
assert.match(refused.error.message, /paired node/);
pass("the shipped function returns the typed refusal for a repository-only parent");

globalThis.__ocParentEntry = { repositoryWorkspaceId: "workspace-id", projectId: "nixfiles" };
const withProject = await call({ projectId: "nixfiles" }).catch((error) => ({ thrown: error }));
if (withProject.ok === false && /paired node/.test(withProject.error?.message ?? "")) {
  fail("a project parent was refused as if its repository were node-only");
}
pass("a project parent is not refused by the new guard");
