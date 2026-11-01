// Acceptance for the repository-parent spawn branch in patch-openclaw-npm-dist.mjs.
//
// Runs the installed, patched package. Proves:
//   - a spawned child of a repository workspace forks the parent's accepted
//     checkpoint (committed, uncommitted and untracked parent state);
//   - the child materializes onto an isolated base, not a fresh URL/ref clone;
//   - the node-side checkpoint capture excludes ignored files such as .env;
//   - a different target agent cannot fork the parent workspace;
//   - session-create rollback removes the forked workspace and its artifact;
//   - the child placement resolves as a repository workspace, so dispatch uses
//     the existing node repository seed and checkpoint services;
//   - non-repository parents keep the pre-change project/worktree route.
//
// Usage: OPENCLAW_PACKAGE_ROOT=/nix/store/...-openclaw-gateway-<version> node <this file>
// Optional baseline A/B: OPENCLAW_BASELINE_ROOT=<pre-change package root>.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";

const packageRoot = process.env.OPENCLAW_PACKAGE_ROOT;
if (!packageRoot) {
  console.error("repository-parent fork test: OPENCLAW_PACKAGE_ROOT is required");
  process.exit(2);
}
const dist = path.join(packageRoot, "dist");
const isolated = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-repository-parent-test-"));
process.env.OPENCLAW_STATE_DIR = path.join(isolated, "state");
process.env.HOME = path.join(isolated, "home");
fs.mkdirSync(process.env.HOME, { recursive: true });

const env = { ...process.env, GIT_CONFIG_NOSYSTEM: "1", GIT_TERMINAL_PROMPT: "0" };
const git = (cwd, ...args) => execFileSync("git", ["-C", cwd, ...args], { env, encoding: "utf8" }).trim();
const node = process.execPath;
const noop = () => {};

function fail(message) {
  console.error(`repository-parent fork test: ${message}`);
  process.exitCode = 1;
  throw new Error(message);
}
function moduleFile(pattern, marker) {
  const matches = fs
    .readdirSync(dist)
    .filter((name) => pattern.test(name))
    .filter((name) => fs.readFileSync(path.join(dist, name), "utf8").includes(marker));
  if (matches.length !== 1) fail(`expected one module for ${pattern} (${marker}), found ${matches.length}`);
  return matches[0];
}
function loadExports(file) {
  const source = fs.readFileSync(path.join(dist, file), "utf8");
  const exports = new Map();
  const match = /export\s*\{([^}]*)\}/u.exec(source);
  if (!match) fail(`${file} has no export list`);
  for (const part of match[1].split(",")) {
    const entry = /^\s*([A-Za-z0-9_$]+)(?:\s+as\s+([A-Za-z0-9_$]+))?\s*$/u.exec(part);
    if (entry) exports.set(entry[1], entry[2] ?? entry[1]);
  }
  return exports;
}
async function importExport(file, exportedName) {
  const exports = loadExports(file);
  const alias = exports.get(exportedName);
  if (!alias) fail(`${file} does not export ${exportedName}`);
  const module = await import(path.join(dist, file));
  return module[alias];
}

const workspaceReconcileFile = moduleFile(/^workspace-reconcile-fs-.*\.mjs$/, "async function captureWorkspaceSnapshot");
const repositoryStoreFile = moduleFile(/^session-accessor\.sqlite-deletion-.*\.mjs$/, "function getSessionRepositoryWorkspaceStore()");
const checkpointFile = moduleFile(/^session-repository-checkpoints-.*\.mjs$/, "async function forkSessionRepositoryWorkspace");
const worktreePreparationFile = moduleFile(/^session-worktree-preparation-.*\.mjs$/, "async function prepareSessionWorktreeCreation");
const manifestScriptsFile = moduleFile(/^workspace-sync-scripts-.*\.mjs$/, "function createRemoteWorkspaceManifestScript");
const placementTargetFile = moduleFile(/^server-worker-placement-session-target-.*\.mjs$/, "async function resolveWorkerPlacementSessionTarget");

const captureWorkspaceSnapshot = await importExport(workspaceReconcileFile, "captureWorkspaceSnapshot");
const serializeWorkspaceManifest = await importExport(workspaceReconcileFile, "serializeWorkspaceManifest");
const getSessionRepositoryWorkspaceStore = await importExport(
  repositoryStoreFile,
  "getSessionRepositoryWorkspaceStore",
);
const stageSessionRepositoryCheckpoint = await importExport(
  checkpointFile,
  "stageSessionRepositoryCheckpoint",
);
const createRemoteWorkspaceManifestScript = await importExport(
  manifestScriptsFile,
  "createRemoteWorkspaceManifestScript",
);
const resolveWorkerPlacementSessionTarget = await importExport(
  placementTargetFile,
  "resolveWorkerPlacementSessionTarget",
);

// ---- 1. A real parent repository workspace with a dirty accepted checkpoint ----
const parentRepo = path.join(isolated, "parent-repo");
fs.mkdirSync(parentRepo);
git(parentRepo, "init", "-q", "-b", "main");
fs.writeFileSync(path.join(parentRepo, "README.md"), "base\n");
fs.mkdirSync(path.join(parentRepo, "secrets"));
fs.writeFileSync(path.join(parentRepo, "secrets", "secrets.yaml"), "sops:\n  encrypted: yes\n");
fs.writeFileSync(path.join(parentRepo, ".gitignore"), ".env\n");
git(parentRepo, "add", ".");
git(parentRepo, "commit", "-q", "-m", "base");
const baseCommit = git(parentRepo, "rev-parse", "HEAD");

const baseSnapshot = await captureWorkspaceSnapshot({ root: parentRepo, baseCommit, signal: undefined });
const baseRaw = (await serializeWorkspaceManifest(baseSnapshot.manifest)).raw;
const store = getSessionRepositoryWorkspaceStore();
let parentWorkspace = await store.create({
  agentId: "main",
  sessionKey: "agent:main:dashboard:parent",
  url: "https://github.com/fleischerdesign/nixfiles",
  requestedRef: "main",
  runSetupScript: false,
  assertCurrent: noop,
});
parentWorkspace = await store.bindBase({
  workspaceId: parentWorkspace.workspaceId,
  expectedRevision: parentWorkspace.revision,
  baseCommit,
  baseManifestHash: baseSnapshot.manifestRef,
  assertCurrent: noop,
});

fs.writeFileSync(path.join(parentRepo, "README.md"), "base\nparent uncommitted change\n");
fs.writeFileSync(path.join(parentRepo, "untracked-parent.txt"), "parent untracked\n");
fs.writeFileSync(path.join(parentRepo, ".env"), "SECRET=must-not-be-captured\n");
const currentSnapshot = await captureWorkspaceSnapshot({ root: parentRepo, baseCommit, signal: undefined });
const currentRaw = (await serializeWorkspaceManifest(currentSnapshot.manifest)).raw;
const stagingRoot = path.join(isolated, "staging");
fs.cpSync(parentRepo, stagingRoot, { recursive: true, filter: (source) => !source.endsWith("/.git") });
const preparedCheckpoint = await stageSessionRepositoryCheckpoint({
  store,
  workspaceId: parentWorkspace.workspaceId,
  expectedRevision: parentWorkspace.revision,
  stagingRoot,
  baseManifestRaw: baseRaw,
  baseManifestRef: baseSnapshot.manifestRef,
  currentManifestRaw: currentRaw,
  currentManifestRef: currentSnapshot.manifestRef,
  assertCurrent: noop,
});
parentWorkspace = await preparedCheckpoint.publish();
assert.equal(parentWorkspace.manifestHash, currentSnapshot.manifestRef, "parent checkpoint was not accepted");

// ---- 2. Drive the patched exported preparation with only the parent lookup stubbed ----
const patchedSource = fs.readFileSync(path.join(dist, worktreePreparationFile), "utf8");
const shim = fs.mkdtempSync(path.join(isolated, "shim-"));
const specs = [...new Set([...patchedSource.matchAll(/(?:from |import )"\.\/([^"]+)"/g)].map((m) => m[1]))];
const storeSpec = specs.find((spec) => spec.startsWith("session-utils-store-"));
if (!storeSpec) fail("worktree preparation no longer imports the session store");
for (const spec of specs) {
  if (spec === storeSpec) continue;
  fs.symlinkSync(path.join(dist, spec), path.join(shim, spec));
}
fs.writeFileSync(
  path.join(shim, storeSpec),
  `export function i(canonicalKey, options = {}) {\n` +
    `  return { entry: globalThis.__ocParentEntry, cfg: globalThis.__ocParentCfg, canonicalKey, storePath: "/tmp/oc-test-store.sqlite", capturedReadSource: undefined };\n` +
    `}\n`,
);
fs.copyFileSync(path.join(dist, worktreePreparationFile), path.join(shim, "worktree-prep.mjs"));
const prepareSessionWorktreeCreation = (await import(path.join(shim, "worktree-prep.mjs"))).n;

async function forkChild(parentEntry, targetAgentId = "main") {
  globalThis.__ocParentEntry = parentEntry;
  globalThis.__ocParentCfg = { agents: { list: [] } };
  return await prepareSessionWorktreeCreation({
    cfg: { agents: { list: [] } },
    target: {
      agentId: targetAgentId,
      key: "agent:main:dashboard:child",
      storePath: "/tmp/oc-test-store.sqlite",
      entry: { sessionId: "child-session-id" },
      titleModelSelection: null,
    },
    signal: undefined,
    commitGuard: noop,
    inheritParentKey: "agent:main:dashboard:parent",
    workspace: undefined,
    name: undefined,
    baseRef: undefined,
    projectGitUrl: undefined,
    deferWorktree: true,
    label: "child",
    titleSource: { message: "task" },
    useRequestedTitleSelection: false,
    runSetupScript: false,
  });
}

const parentEntry = {
  sessionId: "parent-session-id",
  lifecycleRevision: 1,
  repositoryWorkspaceId: parentWorkspace.workspaceId,
  archivedAt: undefined,
};
const fork = await forkChild(parentEntry);
assert.equal(fork.ok, true, `patched preparation failed: ${fork.ok ? "" : fork.error?.message}`);
assert.ok(fork.value.repositoryWorkspaceId, "child did not receive a repository workspace");
assert.equal(fork.value.worktree, undefined, "child must not receive a Gateway worktree");
const childWorkspace = await store.get(fork.value.repositoryWorkspaceId);
assert.ok(childWorkspace, "child repository workspace was not persisted");
assert.notEqual(childWorkspace.workspaceId, parentWorkspace.workspaceId, "child reused the parent workspace");
assert.equal(childWorkspace.agentId, "main");
assert.equal(childWorkspace.sessionKey, "agent:main:dashboard:child");
assert.equal(childWorkspace.baseCommit, parentWorkspace.baseCommit);
assert.equal(childWorkspace.baseManifestHash, parentWorkspace.baseManifestHash);
assert.equal(childWorkspace.manifestHash, parentWorkspace.manifestHash);
assert.notEqual(childWorkspace.checkpointRef, parentWorkspace.checkpointRef, "fork must publish its own checkpoint ref");

// ---- 3. Materialize the child checkpoint over its pinned base ----
const checkout = path.join(isolated, "child-checkout");
execFileSync("git", ["clone", "-q", parentRepo, checkout], { env });
git(checkout, "checkout", "-q", "--detach", baseCommit);
execFileSync(
  "git",
  ["--git-dir", store.artifactPath(childWorkspace.workspaceId), "--work-tree", checkout, "checkout", "-f", childWorkspace.checkpointRef, "--", "."],
  { env },
);
const readCheckout = (relative) => fs.readFileSync(path.join(checkout, relative), "utf8");
assert.equal(readCheckout("README.md"), "base\nparent uncommitted change\n", "uncommitted parent state missing");
assert.equal(readCheckout("untracked-parent.txt"), "parent untracked\n", "untracked parent state missing");
assert.equal(readCheckout("secrets/secrets.yaml"), "sops:\n  encrypted: yes\n", "pinned base content missing");

// ---- 4. Isolation and rollback ----
fs.writeFileSync(path.join(checkout, "child-only.txt"), "child write\n");
const parentAfterChildWrite = await store.get(parentWorkspace.workspaceId);
assert.equal(parentAfterChildWrite.revision, parentWorkspace.revision, "child write changed the parent workspace");
assert.equal(parentAfterChildWrite.manifestHash, parentWorkspace.manifestHash, "child write changed the parent checkpoint");

// ---- 5. Cross-agent authority ----
const crossAgent = await forkChild(parentEntry, "other-agent");
assert.equal(crossAgent.ok, false, "a different target agent forked the parent repository workspace");
if (crossAgent.ok) await crossAgent.value.rollback?.();

// ---- 6. Placement resolves the child as a repository workspace on the inherited node profile ----
const childEntry = {
  sessionId: "child-session-id",
  lifecycleRevision: 1,
  repositoryWorkspaceId: childWorkspace.workspaceId,
  archivedAt: undefined,
};
const target = {
  storePath: "/tmp/oc-test-store.sqlite",
  canonicalKey: "agent:main:dashboard:child",
  agentId: "main",
  storeKeys: ["agent:main:dashboard:child"],
  store: {},
};
const resolved = await resolveWorkerPlacementSessionTarget({
  sessionId: "child-session-id",
  sessionKey: "agent:main:dashboard:child",
  agentId: "main",
  config: {},
  expectedTarget: target,
  readTarget: () => target,
  sessionRuntime: {
    resolveCanonicalSessionEntryFromStoreKeys: () => childEntry,
    managedWorktrees: { findLiveByOwner: async () => undefined },
  },
});
assert.equal(resolved.workspace.kind, "repository", "child placement is not a repository workspace");
assert.equal(resolved.workspace.repository.workspaceId, childWorkspace.workspaceId);
assert.ok(resolved.workspace.repository.baseCommit, "child placement has no pinned base commit");
assert.ok(resolved.workspace.repository.baseManifestHash, "child placement has no pinned base manifest");

// ---- 7. Node checkpoint capture excludes ignored credentials, keeps untracked state ----
const manifestRepo = path.join(isolated, "manifest-repo");
fs.mkdirSync(manifestRepo);
git(manifestRepo, "init", "-q", "-b", "main");
fs.writeFileSync(path.join(manifestRepo, ".gitignore"), ".env\n");
fs.writeFileSync(path.join(manifestRepo, "keep.txt"), "keep\n");
git(manifestRepo, "add", ".");
git(manifestRepo, "commit", "-q", "-m", "base");
const manifestBase = git(manifestRepo, "rev-parse", "HEAD");
fs.writeFileSync(path.join(manifestRepo, ".env"), "SECRET=must-not-be-captured\n");
fs.writeFileSync(path.join(manifestRepo, "untracked-node.txt"), "untracked\n");
const remoteScript = createRemoteWorkspaceManifestScript();
const envelope = JSON.parse(
  execFileSync(node, ["-e", remoteScript, manifestRepo, manifestBase, "eligible", "memo-v1"], {
    env,
    input: "[]",
    encoding: "utf8",
  }),
);
const manifestDigest = envelope.manifestRef.slice(7);
const manifestPath = path.join(process.env.HOME, ".openclaw-worker", "manifests", `${manifestDigest}.json`);
const acceptedManifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const capturedPaths = acceptedManifest.entries.map((entry) => entry.path);
assert.equal(capturedPaths.includes(".env"), false, "node checkpoint captured an ignored credential file");
assert.equal(capturedPaths.includes("untracked-node.txt"), true, "node checkpoint dropped untracked state");

// ---- 8. Rollback cleanup ----
await fork.value.rollback();
assert.equal(await store.get(childWorkspace.workspaceId), undefined, "rollback left the child workspace row");
assert.equal(fs.existsSync(store.artifactPath(childWorkspace.workspaceId)), false, "rollback left the child artifact");

// ---- 9. Non-repository parents keep the existing route ----
const baselineRoot = process.env.OPENCLAW_BASELINE_ROOT;
if (baselineRoot) {
  async function loadBaseline() {
    const baselineDist = path.join(baselineRoot, "dist");
    const name = fs.readdirSync(baselineDist).find((candidate) => /^session-worktree-preparation-.*\.mjs$/.test(candidate));
    const source = fs.readFileSync(path.join(baselineDist, name), "utf8");
    const baselineShim = fs.mkdtempSync(path.join(isolated, "baseline-shim-"));
    const baselineSpecs = [...new Set([...source.matchAll(/(?:from |import )"\.\/([^"]+)"/g)].map((m) => m[1]))];
    const baselineStore = baselineSpecs.find((spec) => spec.startsWith("session-utils-store-"));
    for (const spec of baselineSpecs) {
      if (spec === baselineStore) continue;
      fs.symlinkSync(path.join(baselineDist, spec), path.join(baselineShim, spec));
    }
    fs.writeFileSync(
      path.join(baselineShim, baselineStore),
      `export function i(canonicalKey, options = {}) {\n  return { entry: globalThis.__ocParentEntry, cfg: globalThis.__ocParentCfg, canonicalKey, storePath: "/tmp/oc-test-store.sqlite", capturedReadSource: undefined };\n}\n`,
    );
    fs.copyFileSync(path.join(baselineDist, name), path.join(baselineShim, "worktree-prep.mjs"));
    return (await import(path.join(baselineShim, "worktree-prep.mjs"))).n;
  }
  const runRoute = async (fn, entry) => {
    globalThis.__ocParentEntry = entry;
    globalThis.__ocParentCfg = { agents: { list: [] } };
    try {
      const result = await fn({
        cfg: { agents: { list: [] } },
        target: { agentId: "main", key: "agent:main:dashboard:child", storePath: "/tmp/oc-test-store.sqlite", entry: { sessionId: "c" }, titleModelSelection: null },
        signal: undefined,
        commitGuard: noop,
        inheritParentKey: "agent:main:dashboard:parent",
        workspace: undefined,
        name: undefined,
        baseRef: undefined,
        projectGitUrl: undefined,
        deferWorktree: true,
        label: "child",
        titleSource: { message: "task" },
        useRequestedTitleSelection: false,
        runSetupScript: false,
      });
      return result.ok ? result.value : { error: result.error?.message };
    } catch (error) {
      return { thrown: error?.message };
    }
  };
  const baseline = await loadBaseline();
  for (const [label, entry] of [
    ["managed worktree", { sessionId: "p", lifecycleRevision: 1, worktree: { id: "wt-1" }, archivedAt: undefined }],
    ["project", { sessionId: "p", lifecycleRevision: 1, projectId: "project:missing", archivedAt: undefined }],
  ]) {
    const before = await runRoute(baseline, entry);
    const after = await runRoute(prepareSessionWorktreeCreation, entry);
    assert.deepEqual(after, before, `repository-parent branch changed the ${label} route`);
  }
}

console.log("repository-parent fork test: all assertions passed");
