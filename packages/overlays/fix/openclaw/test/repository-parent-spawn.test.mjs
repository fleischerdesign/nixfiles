// Acceptance for the repository-parent spawn branch in patch-openclaw-npm-dist.mjs.
//
// Runs the installed, patched package, not a model of it. Proves:
//   - the capture controller runs in the required order under the parent's
//     existing turn claim and does not claim, accept or release it;
//   - a parent with a live, uncheckpointed edit (same turn) is captured into the
//     child: committed base, dirty file, untracked file, ignored credential
//     excluded;
//   - the child checkpoint is published in the child workspace only; the parent
//     revision and accepted checkpoint stay untouched;
//   - a changed turn claim or abort stops the capture before any upload;
//   - a failing publish discards the staged result and resumes quiescence;
//   - visible preparation returns the child repository workspace, a stale child
//     checkpoint is refused, and rollback does not depend on parent currency;
//   - the capture is driven through the package's service method, not the
//     exported helper;
//   - a hidden caller cannot run the branch and gets an explicit error instead
//     of the wrong repository, including when it passes a name or baseRef;
//   - a visible spawn cannot bypass capture with an explicit worktree name or
//     baseRef, and no child row or capture is created;
//   - a post-publish failure removes an owned target (created or reused) so a
//     retry is not blocked by an accepted orphan, while a pre-existing valid
//     target is preserved;
//   - valid managed-worktree and explicit-project routes are unchanged against
//     the unpatched baseline package.
//
// Usage:
//   HOME/OPENCLAW_STATE_DIR/XDG_DATA_HOME are set by this file, before imports.
//   OPENCLAW_PACKAGE_ROOT=<gateway>/lib/node_modules/openclaw node <this file>
//   OPENCLAW_BASELINE_ROOT=<unpatched gateway>/lib/node_modules/openclaw (A/B)
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";

if (process.getuid?.() === 0) {
  console.error("repository-parent spawn test: run as an unprivileged user, not root");
  process.exit(2);
}

const packageRoot = process.env.OPENCLAW_PACKAGE_ROOT;
if (!packageRoot) {
  console.error("repository-parent spawn test: OPENCLAW_PACKAGE_ROOT is required");
  process.exit(2);
}
const dist = path.join(packageRoot, "dist");

const isolated = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-repository-parent-test-"));
process.env.OPENCLAW_STATE_DIR = path.join(isolated, "state");
process.env.HOME = path.join(isolated, "home");
process.env.XDG_DATA_HOME = path.join(isolated, "xdg-data");
process.env.XDG_STATE_HOME = path.join(isolated, "xdg-state");
process.env.XDG_CONFIG_HOME = path.join(isolated, "xdg-config");
for (const dir of [
  process.env.OPENCLAW_STATE_DIR,
  process.env.HOME,
  process.env.XDG_DATA_HOME,
  process.env.XDG_STATE_HOME,
  process.env.XDG_CONFIG_HOME,
]) {
  fs.mkdirSync(dir, { recursive: true });
}
const cleanup = () => fs.rmSync(isolated, { recursive: true, force: true });
process.on("exit", cleanup);
process.on("SIGINT", () => {
  cleanup();
  process.exit(130);
});
process.on("SIGTERM", () => {
  cleanup();
  process.exit(143);
});

const env = {
  ...process.env,
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_TERMINAL_PROMPT: "0",
  GIT_AUTHOR_NAME: "OpenClaw Test",
  GIT_AUTHOR_EMAIL: "test@example.invalid",
  GIT_COMMITTER_NAME: "OpenClaw Test",
  GIT_COMMITTER_EMAIL: "test@example.invalid",
};
const git = (cwd, ...args) => execFileSync("git", ["-C", cwd, ...args], { env, encoding: "utf8" }).trim();
const noop = () => {};

let failures = 0;
function fail(message) {
  failures += 1;
  console.error(`repository-parent spawn test: ${message}`);
  throw new Error(message);
}
function moduleFile(root, pattern, marker) {
  const matches = fs
    .readdirSync(root)
    .filter((name) => pattern.test(name))
    .filter((name) => fs.readFileSync(path.join(root, name), "utf8").includes(marker));
  if (matches.length !== 1) fail(`expected one module for ${pattern} (${marker}), found ${matches.length}`);
  return matches[0];
}
function loadExports(root, file) {
  const source = fs.readFileSync(path.join(root, file), "utf8");
  const exports = new Map();
  const blocks = [...source.matchAll(/export\s*\{([^}]*)\}/gu)];
  if (blocks.length === 0) fail(`${file} has no export list`);
  for (const match of blocks) {
    for (const part of match[1].split(",")) {
      const entry = /^\s*([A-Za-z0-9_$]+)(?:\s+as\s+([A-Za-z0-9_$]+))?\s*$/u.exec(part);
      if (entry) exports.set(entry[1], entry[2] ?? entry[1]);
    }
  }
  return exports;
}
async function importExport(root, file, exportedName) {
  const alias = loadExports(root, file).get(exportedName);
  if (!alias) fail(`${file} does not export ${exportedName}`);
  const module = await import(path.join(root, file));
  return module[alias];
}

const workspaceReconcileFile = moduleFile(dist, /^workspace-reconcile-fs-.*\.mjs$/, "async function captureWorkspaceSnapshot");
const repositoryStoreFile = moduleFile(dist, /^session-accessor\.sqlite-deletion-.*\.mjs$/, "function getSessionRepositoryWorkspaceStore()");
const checkpointFile = moduleFile(dist, /^session-repository-checkpoints-.*\.mjs$/, "async function forkSessionRepositoryWorkspace");
const worktreePreparationFile = moduleFile(dist, /^session-worktree-preparation-.*\.mjs$/, "async function prepareSessionWorktreeCreation");
const placementStartupFile = moduleFile(dist, /^server-worker-placement-startup-.*\.mjs$/, "function createRepositoryWorkspaceMutationService");

const captureWorkspaceSnapshot = await importExport(dist, workspaceReconcileFile, "captureWorkspaceSnapshot");
const serializeWorkspaceManifest = await importExport(dist, workspaceReconcileFile, "serializeWorkspaceManifest");
const getSessionRepositoryWorkspaceStore = await importExport(dist, repositoryStoreFile, "getSessionRepositoryWorkspaceStore");
const stageSessionRepositoryCheckpoint = await importExport(dist, checkpointFile, "stageSessionRepositoryCheckpoint");
function serviceModule(root, file) {
  const shim = fs.mkdtempSync(path.join(isolated, "service-shim-"));
  const source = fs.readFileSync(path.join(root, file), "utf8");
  const specs = [...new Set([...source.matchAll(/(?:from |import )"\.\/([^"]+)"/g)].map((m) => m[1]))];
  for (const spec of specs) fs.symlinkSync(path.join(root, spec), path.join(shim, spec));
  fs.writeFileSync(
    path.join(shim, "placement-service.mjs"),
    `${source}\nexport { createRepositoryWorkspaceMutationService };\n`,
  );
  return path.join(shim, "placement-service.mjs");
}
const createRepositoryWorkspaceMutationService = (await import(serviceModule(dist, placementStartupFile)))
  .createRepositoryWorkspaceMutationService;
if (typeof createRepositoryWorkspaceMutationService !== "function") fail("capture service is not a function");
const captureViaService = (deps, params) =>
  createRepositoryWorkspaceMutationService(deps).captureForFork(params);

const store = getSessionRepositoryWorkspaceStore();

function captureModule(root, file, storeSpecFile) {
  const shim = fs.mkdtempSync(path.join(isolated, "shim-"));
  const source = fs.readFileSync(path.join(root, file), "utf8");
  const specs = [...new Set([...source.matchAll(/(?:from |import )"\.\/([^"]+)"/g)].map((m) => m[1]))];
  for (const spec of specs) {
    if (spec === storeSpecFile) continue;
    fs.symlinkSync(path.join(root, spec), path.join(shim, spec));
  }
  fs.writeFileSync(
    path.join(shim, storeSpecFile),
    `export function i(canonicalKey, options = {}) {\n` +
      `  return { entry: globalThis.__ocParentEntry, cfg: globalThis.__ocParentCfg, canonicalKey, storePath: "/tmp/oc-test-store.sqlite", capturedReadSource: undefined };\n` +
      `}\n`,
  );
  fs.copyFileSync(path.join(root, file), path.join(shim, "worktree-prep.mjs"));
  return path.join(shim, "worktree-prep.mjs");
}

async function makeParent(key, root) {
  const baseCommit = git(root, "rev-parse", "HEAD");
  const baseSnapshot = await captureWorkspaceSnapshot({ root, baseCommit, signal: undefined });
  const baseRaw = (await serializeWorkspaceManifest(baseSnapshot.manifest)).raw;
  let workspace = await store.create({
    agentId: "main",
    sessionKey: key,
    url: "https://github.com/fleischerdesign/nixfiles",
    requestedRef: "main",
    runSetupScript: false,
    assertCurrent: noop,
  });
  workspace = await store.bindBase({
    workspaceId: workspace.workspaceId,
    expectedRevision: workspace.revision,
    baseCommit,
    baseManifestHash: baseSnapshot.manifestRef,
    assertCurrent: noop,
  });
  return { workspace, baseSnapshot, baseRaw, baseCommit };
}

function fakeCoordinator(parentWorkspace, options = {}) {
  const calls = [];
  const claim = {
    sessionId: "parent-session-id",
    claimId: "claim-1",
    runId: "run-1",
    placementGeneration: 1,
    owner: { kind: "worker", environmentId: "env-1", ownerEpoch: 1 },
  };
  const placement = {
    sessionId: "parent-session-id",
    sessionKey: "agent:main:dashboard:parent",
    agentId: "main",
    state: "active",
    generation: 1,
    environmentId: "env-1",
    activeOwnerEpoch: 1,
    remoteWorkspaceDir: options.remoteWorkspaceDir ?? "/remote/workspace",
    workerBundleHash: "bundle-1",
    turnClaim: {
      owner: "worker",
      ownerEpoch: 1,
      claimId: "claim-1",
      runId: "run-1",
      generation: 1,
    },
  };
  const environment = {
    environmentId: "env-1",
    state: "attached",
    destroyRequestedAtMs: null,
    ownerEpoch: 1,
    leaseId: "lease-1",
    attachedSessionIds: ["parent-session-id"],
    bootstrapReceipt: {
      bundleHash: "bundle-1",
      protocolFeatures: ["worker-execution-context-v2", "worker-execution-authority-v1"],
    },
  };
  let claimCurrent = options.claimCurrent !== false;
  let resumed = false;
  const deps = {
    placements: {
      async getAsync() {
        return placement;
      },
      get(sessionId) {
        assert.equal(sessionId, placement.sessionId);
        return placement;
      },
      validateTurnClaim(value) {
        calls.push("validateTurnClaim");
        return claimCurrent && value.claimId === claim.claimId;
      },
    },
    environments: {
      get(environmentId) {
        return environmentId === environment.environmentId ? environment : undefined;
      },
      async startTunnel({ environmentId, ownerEpoch }) {
        calls.push("startTunnel");
        return {
          environmentId,
          ownerEpoch,
          async quiesceWorkspace(dir) {
            calls.push(`quiesce:${dir}`);
            return {
              assertActive() {
                calls.push("quiesceActive");
                if (!claimCurrent) throw new Error("quiescence lost its turn claim");
              },
              async resume() {
                calls.push("resume");
                resumed = true;
              },
            };
          },
          async reconcileWorkspace(request) {
            calls.push("reconcile");
            assert.equal(request.source.kind, "repository");
            assert.equal(request.baseManifestRef, parentWorkspace.baseManifestHash);
            assert.equal(request.source.referenceManifestRef, parentWorkspace.manifestHash ?? parentWorkspace.baseManifestHash);
            const prepared = await request.source.prepareCheckpoint(options.payload);
            if (options.reconcileError) throw options.reconcileError;
            return {
              manifestRef: options.payload.currentManifestRef,
              changed: true,
              async verifyStable() {
                calls.push("verifyStable");
              },
              async verifyLocalStable() {
                calls.push("verifyLocalStable");
                await prepared.verify();
              },
              async publishStagedResult() {
                calls.push("publish");
                if (options.publishError) throw options.publishError;
                await prepared.publish();
                if (options.postPublishError) throw options.postPublishError;
              },
              async discardPreparedStagedResult() {
                calls.push("discard");
                await prepared.discard();
              },
            };
          },
        };
      },
    },
    workspaceOperations: {
      async run(environmentId, run) {
        calls.push(`workspaceOperations:${environmentId}`);
        return await run();
      },
    },
    async resolveWorkspace() {
      calls.push("resolveWorkspace");
      return { kind: "repository", repository: { ...parentWorkspace, revision: parentWorkspace.revision } };
    },
  };
  return {
    deps,
    calls,
    claim,
    placement,
    setClaimCurrent(value) {
      claimCurrent = value;
    },
    wasResumed: () => resumed,
  };
}

function liveTree(root, baseCommit) {
  fs.writeFileSync(path.join(root, "README.md"), "base\nsame-turn parent change\n");
  fs.writeFileSync(path.join(root, "untracked-parent.txt"), "same-turn untracked\n");
  fs.writeFileSync(path.join(root, ".env"), "SECRET=must-not-be-captured\n");
  return captureWorkspaceSnapshot({ root, baseCommit, signal: undefined });
}

function stagingCopy(root, exclude = []) {
  const staging = path.join(isolated, `staging-${Date.now()}-${Math.random().toString(16).slice(2)}`);
  fs.cpSync(root, staging, {
    recursive: true,
    filter: (source) => !source.endsWith("/.git") && !exclude.some((name) => source.endsWith(`/${name}`)),
  });
  return staging;
}

async function childWithBase(parent, key) {
  let child = await store.create({
    agentId: "main",
    sessionKey: key,
    url: parent.workspace.url,
    requestedRef: "main",
    runSetupScript: false,
    assertCurrent: noop,
  });
  child = await store.bindBase({
    workspaceId: child.workspaceId,
    expectedRevision: child.revision,
    baseCommit: parent.baseCommit,
    baseManifestHash: parent.baseSnapshot.manifestRef,
    assertCurrent: noop,
  });
  return child;
}

function readCheckout(workspaceId, checkpointRef, parentRoot, baseCommit) {
  const checkout = path.join(isolated, `checkout-${workspaceId}`);
  execFileSync("git", ["clone", "-q", parentRoot, checkout], { env });
  git(checkout, "checkout", "-q", "--detach", baseCommit);
  execFileSync(
    "git",
    ["--git-dir", store.artifactPath(workspaceId), "--work-tree", checkout, "checkout", "-f", checkpointRef],
    { env, cwd: checkout },
  );
  return (relative) => fs.readFileSync(path.join(checkout, relative), "utf8");
}

// ---- 1. Capture the live, uncheckpointed parent tree into a child workspace ----
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
const parent = await makeParent("agent:main:dashboard:parent", parentRepo);
assert.equal(parent.workspace.checkpointRef, null, "test parent must start without an accepted checkpoint");
await liveTree(parentRepo, baseCommit);
// The node upload applies the existing ignore policy before the gateway sees a
// manifest. This fixture mirrors that payload; the upload script is not re-tested
// here, because it is not part of this branch.
const stagingRoot = stagingCopy(parentRepo, [".env"]);
const live = await captureWorkspaceSnapshot({ root: stagingRoot, baseCommit, signal: undefined });
const liveRaw = (await serializeWorkspaceManifest(live.manifest)).raw;
const payload = {
  stagingRoot,
  baseManifestRaw: parent.baseRaw,
  baseManifestRef: parent.baseSnapshot.manifestRef,
  currentManifestRaw: liveRaw,
  currentManifestRef: live.manifestRef,
};

const child = await childWithBase(parent, "agent:main:dashboard:child");
const controller = fakeCoordinator(parent.workspace, { payload });
const captured = await captureViaService(controller.deps, {
  sessionId: "parent-session-id",
  sessionKey: "agent:main:dashboard:parent",
  agentId: "main",
  sourceWorkspaceId: parent.workspace.workspaceId,
  target: { workspaceId: child.workspaceId, expectedRevision: child.revision },
  signal: undefined,
  assertCurrent: noop,
});
const childAfter = await store.get(child.workspaceId);
assert.equal(captured.manifestRef, live.manifestRef);
assert.equal(childAfter.manifestHash, live.manifestRef, "child did not accept the live manifest");
assert.ok(childAfter.checkpointRef, "child has no accepted checkpoint");
const readChild = readCheckout(child.workspaceId, childAfter.checkpointRef, parentRepo, baseCommit);
assert.equal(readChild("README.md"), "base\nsame-turn parent change\n", "same-turn edit missing in child");
assert.equal(readChild("untracked-parent.txt"), "same-turn untracked\n", "untracked same-turn file missing in child");
assert.equal(readChild("secrets/secrets.yaml"), "sops:\n  encrypted: yes\n", "pinned base content missing");
assert.equal(fs.existsSync(path.join(isolated, `checkout-${child.workspaceId}`, ".env")), false, "ignored credential captured");
const parentAfter = await store.get(parent.workspace.workspaceId);
assert.equal(parentAfter.revision, parent.workspace.revision, "capture changed the parent revision");
assert.equal(parentAfter.checkpointRef, null, "capture accepted a checkpoint on the parent");
assert.equal(parentAfter.manifestHash, parent.workspace.manifestHash, "capture changed the parent manifest");
const expectedOrder = [
  "workspaceOperations:env-1",
  "resolveWorkspace",
  "startTunnel",
  "quiesce:/remote/workspace",
  "reconcile",
  "quiesceActive",
  "verifyStable",
  "verifyLocalStable",
  "quiesceActive",
  "verifyStable",
  "verifyLocalStable",
  "publish",
];
const observedOrder = controller.calls.filter((call) => call !== "validateTurnClaim");
assert.deepEqual(observedOrder, [...expectedOrder, "resume"], `capture order: ${controller.calls.join(" -> ")}`);
assert.equal(controller.calls.filter((call) => call === "resume").length, 1, "quiescence was not resumed exactly once");
assert.equal(controller.calls.includes("claimWorkspaceMutationResult"), false, "capture claimed a workspace result");
console.log("ok 1: live same-turn capture, child publish, parent untouched");

// ---- 2. A changed claim stops the capture before upload ----
const blocked = fakeCoordinator(parent.workspace, { payload });
blocked.setClaimCurrent(false);
const blockedChild = await childWithBase(parent, "agent:main:dashboard:blocked-child");
await assert.rejects(
  captureViaService(blocked.deps, {
    sessionId: "parent-session-id",
    sessionKey: "agent:main:dashboard:parent",
    agentId: "main",
    sourceWorkspaceId: parent.workspace.workspaceId,
    target: { workspaceId: blockedChild.workspaceId, expectedRevision: blockedChild.revision },
    signal: undefined,
    assertCurrent: noop,
  }),
  /authority changed/,
);
assert.equal(blocked.calls.includes("reconcile"), false, "changed claim still started the upload");
assert.equal((await store.get(blockedChild.workspaceId)).checkpointRef, null);
console.log("ok 2: claim mismatch fails before upload");

// ---- 3. A failed publish discards the staged result and resumes quiescence ----
const failing = fakeCoordinator(parent.workspace, {
  payload: { ...payload, stagingRoot: stagingCopy(parentRepo) },
  publishError: new Error("simulated publish failure"),
});
const failingChild = await childWithBase(parent, "agent:main:dashboard:failing-child");
await assert.rejects(
  captureViaService(failing.deps, {
    sessionId: "parent-session-id",
    sessionKey: "agent:main:dashboard:parent",
    agentId: "main",
    sourceWorkspaceId: parent.workspace.workspaceId,
    target: { workspaceId: failingChild.workspaceId, expectedRevision: failingChild.revision },
    signal: undefined,
    assertCurrent: noop,
  }),
  /simulated publish failure/,
);
assert.equal(failing.calls.includes("discard"), true, "failed publish did not discard the prepared result");
assert.equal(failing.wasResumed(), true, "failed publish did not resume quiescence");
assert.equal((await store.get(failingChild.workspaceId)).checkpointRef, null, "failed publish accepted a checkpoint");
console.log("ok 3: publish failure discards and resumes");

// ---- 4. Preparation integration: visible placed path, rollback, retry, authority ----
const prepareStoreSpec = [...fs.readFileSync(path.join(dist, worktreePreparationFile), "utf8").matchAll(/from "\.\/(session-utils-store-[^"]+)"/g)][0]?.[1];
if (!prepareStoreSpec) fail("worktree preparation no longer imports the session store");
const preparePath = captureModule(dist, worktreePreparationFile, prepareStoreSpec);
const prepareSessionWorktreeCreation = (await import(preparePath)).n;

const parentEntry = {
  sessionId: "parent-session-id",
  lifecycleRevision: 1,
  repositoryWorkspaceId: parent.workspace.workspaceId,
  archivedAt: undefined,
};
function captureService(recorder) {
  return {
    async captureForFork(params) {
      recorder.push("captureForFork");
      assert.equal(params.sessionId, "parent-session-id");
      assert.equal(params.agentId, "main");
      assert.ok(params.target.workspaceId);
      assert.ok(Number.isSafeInteger(params.target.expectedRevision));
      await captureViaService(controller.deps, {
        ...params,
        sourceWorkspaceId: parent.workspace.workspaceId,
      });
    },
  };
}
async function runPrepare({ key = "agent:main:dashboard:prepared-child", agentId = "main", inherited = true, selectors = {} } = {}) {
  globalThis.__ocParentEntry = parentEntry;
  globalThis.__ocParentCfg = { agents: { list: [] } };
  return await prepareSessionWorktreeCreation({
    cfg: { agents: { list: [] } },
    target: {
      agentId,
      key,
      storePath: "/tmp/oc-test-store.sqlite",
      entry: undefined,
      titleModelSelection: null,
    },
    signal: undefined,
    commitGuard: noop,
    inheritParentKey: "agent:main:dashboard:parent",
    repositoryParentInheritance: inherited,
    repositoryCaptureService: captureService(runPrepare.calls),
    workspace: undefined,
    name: undefined,
    baseRef: undefined,
    projectGitUrl: undefined,
    deferWorktree: true,
    label: "child",
    titleSource: { message: "task" },
    useRequestedTitleSelection: false,
    runSetupScript: false,
    ...selectors,
  });
}
runPrepare.calls = [];
const preparedResult = await runPrepare();
assert.equal(preparedResult.ok, true, `preparation failed: ${preparedResult.ok ? "" : preparedResult.error?.message}`);
assert.ok(preparedResult.value.repositoryWorkspaceId, "prepared child has no repository workspace");
assert.equal(preparedResult.value.worktree, undefined, "prepared child must not get a Gateway worktree");
assert.equal((await store.get(parent.workspace.workspaceId)).checkpointRef, null, "preparation accepted a parent checkpoint");
const preparedChild = await store.get(preparedResult.value.repositoryWorkspaceId);
assert.ok(preparedChild.checkpointRef, "prepared child has no accepted checkpoint");
const parentBeforeRollback = await store.get(parent.workspace.workspaceId);
globalThis.__ocParentEntry = undefined;
await preparedResult.value.rollback();
assert.equal(await store.get(preparedChild.workspaceId), undefined, "rollback left the child workspace row");
assert.equal(fs.existsSync(store.artifactPath(preparedChild.workspaceId)), false, "rollback left the child artifact");
assert.equal((await store.get(parent.workspace.workspaceId)).revision, parentBeforeRollback.revision, "rollback touched the parent");
globalThis.__ocParentEntry = parentEntry;
console.log("ok 4: preparation returns an isolated child and parent-independent rollback");

// ---- 5. Retry uses the live target revision; an accepted stale child is refused ----
runPrepare.calls.length = 0;
const retryChild = await childWithBase(parent, "agent:main:dashboard:retry-child");
const retryResult = await runPrepare({ key: "agent:main:dashboard:retry-child" });
assert.equal(retryResult.ok, true, `retry failed: ${retryResult.ok ? "" : retryResult.error?.message}`);
assert.equal(runPrepare.calls[0], "captureForFork", "retry did not capture");
const retryAfter = await store.get(retryChild.workspaceId);
assert.ok(retryAfter.checkpointRef, "retry did not accept a checkpoint");
assert.notEqual(retryAfter.revision, retryChild.revision, "retry reused the stale revision");

runPrepare.calls.length = 0;
const acceptedChild = await childWithBase(parent, "agent:main:dashboard:accepted-child");
await captureViaService(controller.deps, {
  sessionId: "parent-session-id",
  sessionKey: "agent:main:dashboard:parent",
  agentId: "main",
  sourceWorkspaceId: parent.workspace.workspaceId,
  target: { workspaceId: acceptedChild.workspaceId, expectedRevision: acceptedChild.revision },
  signal: undefined,
  assertCurrent: noop,
});
const stale = await runPrepare({ key: "agent:main:dashboard:accepted-child" });
assert.equal(stale.ok, false, "an already accepted child checkpoint was reused");
assert.match(stale.error.message, /already has an accepted checkpoint/);
assert.equal(runPrepare.calls.length, 0, "stale child reached capture");
const acceptedAfter = await store.get(acceptedChild.workspaceId);
assert.ok(acceptedAfter, "stale refusal deleted the pre-existing accepted child");
assert.equal(acceptedAfter.agentId, "main", "stale refusal changed the child owner agent");
assert.equal(acceptedAfter.sessionKey, "agent:main:dashboard:accepted-child", "stale refusal changed the child owner session");
assert.ok(acceptedAfter.checkpointRef, "stale refusal removed the pre-existing accepted checkpoint");
console.log("ok 5: retry is revision-fresh and a stale child checkpoint is refused");

// ---- 6. Hidden caller gets an explicit error, never the branch ----
runPrepare.calls.length = 0;
const hidden = await runPrepare({ inherited: false, key: "agent:main:dashboard:hidden-child" });
assert.equal(hidden.ok, false, "hidden caller ran the repository-parent branch");
assert.match(hidden.error.message, /hidden subagents cannot inherit it/);
assert.equal(runPrepare.calls.length, 0, "hidden caller reached capture");
assert.equal(await store.find({ agentId: "main", sessionKey: "agent:main:dashboard:hidden-child" }), undefined);
console.log("ok 6: hidden caller is explicitly refused");

// ---- 7. Cross-agent target cannot capture the parent workspace ----
runPrepare.calls.length = 0;
const cross = await runPrepare({ agentId: "other-agent", key: "agent:other-agent:dashboard:child" });
assert.equal(cross.ok, false, "a different target agent captured the parent workspace");
assert.equal(runPrepare.calls.length, 0, "cross-agent target reached capture");
console.log("ok 7: cross-agent authority unchanged");

// ---- 8. Explicit worktree name/baseRef cannot fall back to the Gateway default ----
for (const [label, options] of [
  ["hidden name", { inherited: false, key: "agent:main:dashboard:hidden-named-child", selectors: { name: "named-worktree" } }],
  ["visible name", { key: "agent:main:dashboard:visible-named-child", selectors: { name: "named-worktree" } }],
  ["visible baseRef", { key: "agent:main:dashboard:visible-baseref-child", selectors: { baseRef: "main" } }],
]) {
  runPrepare.calls.length = 0;
  const refused = await runPrepare(options);
  assert.equal(refused.ok, false, `${label} fell through to the Gateway default workspace`);
  assert.match(refused.error.message, /repository workspace cannot use an explicit worktree name or baseRef/);
  assert.equal(runPrepare.calls.length, 0, `${label} reached capture`);
  assert.equal(
    await store.find({ agentId: "main", sessionKey: options.key }),
    undefined,
    `${label} left a child workspace row`,
  );
}
console.log("ok 8: explicit name/baseRef is refused before store or capture");

// ---- 9. A post-publish failure cleans the target and does not block a retry ----
const postPublishError = new Error("simulated post-publish source change");
const postPublishExisting = await childWithBase(parent, "agent:main:dashboard:postpublish-existing");
const failingAfterPublish = fakeCoordinator(parent.workspace, {
  payload: { ...payload, stagingRoot: stagingCopy(parentRepo) },
  postPublishError,
});
const existingFailed = await runPrepare({
  key: "agent:main:dashboard:postpublish-existing",
  selectors: {
    repositoryCaptureService: {
      async captureForFork(params) {
        await captureViaService(failingAfterPublish.deps, params);
      },
    },
  },
});
assert.equal(existingFailed.ok, false, "post-publish failure was reported as success");
assert.equal(await store.get(postPublishExisting.workspaceId), undefined, "post-publish failure left an accepted orphan");
assert.equal(fs.existsSync(store.artifactPath(postPublishExisting.workspaceId)), false, "post-publish failure left the child artifact");
const retryAfterExisting = await runPrepare({ key: "agent:main:dashboard:postpublish-existing" });
assert.equal(retryAfterExisting.ok, true, `retry after a post-publish failure was blocked: ${retryAfterExisting.error?.message}`);
assert.ok((await store.get(retryAfterExisting.value.repositoryWorkspaceId)).checkpointRef, "retry after cleanup has no checkpoint");
console.log("ok 9: post-publish existing-target failure cleans up and retries");

// ---- 10. A created target that fails after publish is removed as well ----
const createdKey = "agent:main:dashboard:postpublish-created";
const failingCreated = fakeCoordinator(parent.workspace, {
  payload: { ...payload, stagingRoot: stagingCopy(parentRepo) },
  postPublishError,
});
const createdFailed = await runPrepare({
  key: createdKey,
  selectors: {
    repositoryCaptureService: {
      async captureForFork(params) {
        await captureViaService(failingCreated.deps, params);
      },
    },
  },
});
assert.equal(createdFailed.ok, false, "created post-publish failure was reported as success");
assert.equal(await store.find({ agentId: "main", sessionKey: createdKey }), undefined, "created post-publish failure left an orphan");
const retryAfterCreated = await runPrepare({ key: createdKey });
assert.equal(retryAfterCreated.ok, true, `retry after a created-target failure was blocked: ${retryAfterCreated.error?.message}`);
console.log("ok 10: post-publish created-target failure cleans up and retries");

// ---- 11. Baseline A/B: managed worktree and explicit project routes ----
const baselineRoot = process.env.OPENCLAW_BASELINE_ROOT;
if (!baselineRoot) {
  fail("OPENCLAW_BASELINE_ROOT is required for the mandatory A/B fixtures");
}
const baselineDist = path.join(baselineRoot, "dist");
const baselineWorktreeFile = moduleFile(baselineDist, /^session-worktree-preparation-.*\.mjs$/, "async function prepareSessionWorktreeCreation");
const baselineStoreSpec = [...fs.readFileSync(path.join(baselineDist, baselineWorktreeFile), "utf8").matchAll(/from "\.\/(session-utils-store-[^"]+)"/g)][0]?.[1];
if (!baselineStoreSpec) fail("baseline worktree preparation no longer imports the session store");
const baselinePath = captureModule(baselineDist, baselineWorktreeFile, baselineStoreSpec);
const baselinePrepare = (await import(baselinePath)).n;

async function routeResult(run, targetEntry, extra = {}) {
  globalThis.__ocParentEntry = parentEntry;
  globalThis.__ocParentCfg = { agents: { list: [] } };
  try {
    const result = await run({
      cfg: { agents: { list: [] } },
      target: { agentId: "main", key: "agent:main:dashboard:ab-child", storePath: "/tmp/oc-test-store.sqlite", entry: targetEntry, titleModelSelection: null },
      signal: undefined,
      commitGuard: noop,
      inheritParentKey: "agent:main:dashboard:parent",
      repositoryParentInheritance: true,
      repositoryCaptureService: { async captureForFork() { throw new Error("A/B fixture reached the repository branch"); } },
      workspace: undefined,
      name: undefined,
      baseRef: undefined,
      projectGitUrl: undefined,
      deferWorktree: true,
      label: "child",
      titleSource: { message: "task" },
      useRequestedTitleSelection: false,
      runSetupScript: false,
      ...extra,
    });
    return result.ok ? { value: result.value } : { error: result.error?.message };
  } catch (error) {
    return { thrown: error?.message };
  }
}
const routeFixtures = [
  [
    "managed worktree",
    { worktree: { id: "wt-1", canonicalWorkspaceDir: parentRepo, repoRoot: parentRepo } },
    {},
  ],
  [
    "explicit project",
    { projectId: "project:fixture" },
    { workspace: parentRepo },
  ],
];
for (const [label, targetEntry, extra] of routeFixtures) {
  const before = await routeResult(baselinePrepare, targetEntry, extra);
  const after = await routeResult(prepareSessionWorktreeCreation, targetEntry, extra);
  assert.deepEqual(after, before, `repository-parent branch changed the ${label} route`);
  assert.equal(before.error, undefined, `${label} fixture did not succeed: ${before.error ?? before.thrown}`);
}
console.log("ok 11: baseline A/B unchanged for managed worktree and explicit project");

if (failures > 0) process.exit(1);
console.log("repository-parent spawn test: all assertions passed");
