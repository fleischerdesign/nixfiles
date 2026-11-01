#!/usr/bin/env node
// Compose with nix-openclaw's dist-patch hook, then relax hardlink rejection for
// skill-tree reads that point at an immutable, root-owned Nix store output.
//
// The upstream script already patches plugin and Control UI hardlink decisions but
// leaves `readSkillBundleTree` unconditional, so a worker turn fails with
// `hardlink: hardlinked path not allowed | INVALID_BUNDLE` whenever
// `auto-optimise-store` hardlinked a bundled, custodian or plugin skill file.
//
// This script runs the upstream patch first, installs the policy module next to the
// bundle, and changes exactly the one decision in `readSkillBundleTree`. It fails
// loudly when the upstream contract moves, so a release bump cannot silently build an
// unpatched package.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

function fail(message) {
  console.error(`skill hardlink policy: ${message}`);
  process.exit(1);
}

const upstream = process.env.OPENCLAW_UPSTREAM_PATCH_NPM_DIST_SCRIPT;
if (!upstream) fail("OPENCLAW_UPSTREAM_PATCH_NPM_DIST_SCRIPT is required");
execFileSync(process.execPath, [upstream], { stdio: "inherit", env: process.env });

const root = process.env.OPENCLAW_PACKAGE_ROOT;
if (!root) fail("OPENCLAW_PACKAGE_ROOT is required");
const dist = path.join(root, "dist");
if (!fs.existsSync(dist)) fail(`dist directory missing: ${dist}`);

const policySource = process.env.OPENCLAW_SKILL_HARDLINK_POLICY;
if (!policySource || !fs.existsSync(policySource)) {
  fail(`policy module missing: ${policySource ?? "(unset)"}`);
}

const marker = "Skill tree file could not be read";
const owners = fs
  .readdirSync(dist, { withFileTypes: true })
  .filter((entry) => (entry.isFile() || entry.isSymbolicLink()) && /\.m?js$/.test(entry.name))
  .filter((entry) => {
    const source = fs.readFileSync(path.join(dist, entry.name), "utf8");
    return source.includes(marker) && source.includes("function readSkillBundleTree(");
  });
if (owners.length !== 1) fail(`expected exactly one skill bundle chunk, found ${owners.length}`);

const file = path.join(dist, owners[0].name);
let source = fs.readFileSync(file, "utf8");

const importLine =
  'import { resourceHardlinkPolicy as __ocResourceHardlinkPolicy } from "./nix-skill-hardlink-policy.mjs";';
if (source.includes("__ocResourceHardlinkPolicy")) {
  console.log("skill hardlink policy: already applied");
} else {

const readCall = "const read = await safeRoot.read(entry.relativePath, {";
const callCount = source.split(readCall).length - 1;
if (callCount !== 1) fail(`expected one skill-tree read call, found ${callCount}`);

const start = source.indexOf(readCall);
const window = source.slice(start, start + 256);
if (!window.includes('hardlinks: "reject",')) {
  fail("skill-tree read call no longer carries the expected hardlink decision");
}

const patchedWindow = window.replace(
  'hardlinks: "reject",',
  "hardlinks: __ocResourceHardlinkPolicy(directory),",
);
source = source.slice(0, start) + patchedWindow + source.slice(start + window.length);

const policyTarget = path.join(dist, "nix-skill-hardlink-policy.mjs");
fs.copyFileSync(policySource, policyTarget);
fs.chmodSync(policyTarget, 0o444);
// The npm cache may hand back read-only files; write, then restore the package mode.
fs.chmodSync(file, 0o644);
fs.writeFileSync(file, `${importLine}\n${source}`);
fs.chmodSync(file, 0o444);
console.log(`skill hardlink policy: patched ${owners[0].name} and installed ${path.basename(policyTarget)}`);
}

// ---------------------------------------------------------------------------
// Repository-parent spawn branch.
//
// A worker `sessions_spawn` from a session placed on a node forces
// `worktree: true` and carries no repository selector, so the child inherits
// only the parent's project id or managed worktree. A parent whose workspace is
// a session repository workspace (the New Chat -> GitHub flow) has neither, and
// the child falls back to the Gateway's default agent workspace: the wrong
// repository. The installed build already ships every primitive a correct child
// needs - the repository workspace store, checkpoint publication and the
// `forkSessionRepositoryWorkspace` service used by session fork - but the spawn
// preparation never calls them.
//
// This patch adds one branch to `prepareSessionWorktreeCreation`: when the
// inherited parent owns a repository workspace, fork that workspace for the
// child instead of preparing a Gateway worktree. The fork copies the parent's
// pinned base and accepted checkpoint, so the child starts on an isolated
// repository checkout of the parent's current committed, uncommitted and
// untracked state. A fresh URL/ref clone would lose that state and is
// deliberately not used.

function findOne(label, predicate) {
  const matches = fs
    .readdirSync(dist, { withFileTypes: true })
    .filter((entry) => (entry.isFile() || entry.isSymbolicLink()) && /\.m?js$/.test(entry.name))
    .map((entry) => entry.name)
    .filter((name) => predicate(fs.readFileSync(path.join(dist, name), "utf8"), name));
  if (matches.length !== 1) fail(`${label}: expected exactly one owner, found ${matches.length}`);
  return matches[0];
}

const worktreeFile = findOne(
  "session worktree preparation",
  (source) =>
    source.includes("async function prepareSessionWorktreeCreation(params) {") &&
    source.includes("async function resolveSpawnParentWorktreeSource(parentSessionKey, agentId, options = {}) {"),
);

const forkFile = findOne(
  "repository checkpoint fork service",
  (source) =>
    source.includes("async function forkSessionRepositoryWorkspace(params) {") &&
    /export\s*\{[^}]*forkSessionRepositoryWorkspace\s+as\s+([A-Za-z0-9_$]+)/u.test(source),
);
const forkAlias = /export\s*\{[^}]*forkSessionRepositoryWorkspace\s+as\s+([A-Za-z0-9_$]+)/u.exec(
  fs.readFileSync(path.join(dist, forkFile), "utf8"),
)?.[1];
if (!forkAlias) fail(`repository checkpoint fork service: export alias missing in ${forkFile}`);

const repositoryStoreFile = findOne(
  "session repository workspace store",
  (source) =>
    source.includes("function getSessionRepositoryWorkspaceStore() {") &&
    /getSessionRepositoryWorkspaceStore\s+as\s+([A-Za-z0-9_$]+)/u.test(source),
);
const repositoryStoreAlias =
  /getSessionRepositoryWorkspaceStore\s+as\s+([A-Za-z0-9_$]+)/u.exec(
    fs.readFileSync(path.join(dist, repositoryStoreFile), "utf8"),
  )?.[1];
if (!repositoryStoreAlias) fail(`session repository workspace store: export alias missing in ${repositoryStoreFile}`);

const worktreePath = path.join(dist, worktreeFile);
let worktreeSource = fs.readFileSync(worktreePath, "utf8");

if (worktreeSource.includes("__ocForkSessionRepositoryWorkspace")) {
  fail("repository-parent spawn branch is already patched");
}

const worktreeAnchor = "import { isDeepStrictEqual } from \"node:util\";";
if (worktreeSource.split(worktreeAnchor).length - 1 !== 1) {
  fail("repository-parent spawn branch: import anchor moved");
}
worktreeSource = worktreeSource.replace(
  worktreeAnchor,
  `${worktreeAnchor}\nimport { ${forkAlias} as __ocForkSessionRepositoryWorkspace } from "./${forkFile}";\nimport { ${repositoryStoreAlias} as __ocGetSessionRepositoryWorkspaceStore } from "./${repositoryStoreFile}";`,
);

const helperAnchor = "async function prepareSessionWorktreeCreation(params) {";
if (worktreeSource.split(helperAnchor).length - 1 !== 1) {
  fail("repository-parent spawn branch: preparation anchor moved");
}

const helpers = `/** Resolve an inherited parent repository workspace as a spawn source. */
async function __ocResolveSpawnParentRepositoryWorkspace(parentSessionKey, agentId, options = {}) {
	const parent = loadGatewaySessionEntryReadOnly(parentSessionKey, { agentId });
	const repositoryWorkspaceId = normalizeOptionalString(parent.entry?.repositoryWorkspaceId);
	if (!repositoryWorkspaceId || parent.entry?.worktree) return;
	const fields = ["sessionId", "archivedAt", "repositoryWorkspaceId", "worktree"];
	const refuse = () => {
		throw new SessionWorktreeSourceChangedError("Spawn parent repository changed; retry from its current session");
	};
	const assertRouting = captureSessionMutationRouting(parent.cfg, refuse);
	const assertParentCurrent = captureSessionEntrySourceAssertion({
		scope: {
			agentId,
			sessionKey: parent.canonicalKey,
			storePath: parent.storePath
		},
		readSource: parent.capturedReadSource,
		expected: parent.entry,
		fields,
		assertCurrent: () => {
			const current = loadGatewaySessionEntryReadOnly(parent.canonicalKey, { agentId });
			if (!current.entry || fields.some((field) => !isDeepStrictEqual(current.entry?.[field], parent.entry?.[field]))) refuse();
		},
		assertHostCurrent: () => {
			options.signal?.throwIfAborted();
			assertRouting(getRuntimeConfig());
		},
		refuse
	});
	return {
		agentId,
		parentKey: parent.canonicalKey,
		workspaceId: repositoryWorkspaceId,
		assertParentCurrent
	};
}
/** Fork the parent's accepted repository checkpoint into an isolated child workspace. */
async function __ocPrepareSpawnChildRepositoryWorkspace(params) {
	const repositories = __ocGetSessionRepositoryWorkspaceStore();
	const source = params.source;
	const assertCurrent = () => {
		params.signal?.throwIfAborted();
		params.commitGuard();
		source.assertParentCurrent();
	};
	let preparedSource;
	let existing;
	try {
		preparedSource = await repositories.prepare(source.workspaceId);
		existing = await repositories.find({
			agentId: params.target.agentId,
			sessionKey: params.target.key
		});
	} catch (error) {
		return err(errorShape(ErrorCodes.UNAVAILABLE, formatErrorMessage(error)));
	}
	const workspace = preparedSource.current();
	if (!workspace || workspace.workspaceId !== source.workspaceId || workspace.agentId !== params.target.agentId || workspace.sessionKey !== source.parentKey) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn parent repository workspace changed; retry from its current session"));
	if (!workspace.baseCommit || !workspace.checkpointRef) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn parent repository has no accepted checkpoint; let the parent finish a turn and retry"));
	assertCurrent();
	if (existing) {
		if (existing.url !== workspace.url || existing.baseCommit !== workspace.baseCommit) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn child repository workspace does not match its parent; delete the child session and retry"));
		return ok({ repositoryWorkspaceId: existing.workspaceId });
	}
	let target;
	try {
		target = await __ocForkSessionRepositoryWorkspace({
			store: repositories,
			sourceWorkspaceId: source.workspaceId,
			agentId: params.target.agentId,
			sessionKey: params.target.key,
			assertCurrent
		});
	} catch (error) {
		return err(errorShape(ErrorCodes.UNAVAILABLE, formatErrorMessage(error)));
	}
	assertCurrent();
	return ok({
		repositoryWorkspaceId: target.workspaceId,
		rollback: async () => {
			source.assertParentCurrent();
			await repositories.delete({
				workspaceId: target.workspaceId,
				assertCurrent: () => source.assertParentCurrent()
			});
		}
	});
}
${helperAnchor}`;

worktreeSource = worktreeSource.replace(helperAnchor, helpers);

const inheritedLine =
  "\tconst inheritedSource = params.inheritParentKey && !acceptedWorktree && !acceptedPending ? await resolveSpawnParentWorktreeSource(params.inheritParentKey, lifecycleTarget.agentId, { signal }) : void 0;";
if (worktreeSource.split(inheritedLine).length - 1 !== 1) {
  fail("repository-parent spawn branch: inherited source expression moved");
}

const repositoryBranch = `\tconst repositoryParentSource = params.inheritParentKey && !acceptedWorktree && !acceptedPending && !params.workspace && !params.projectGitUrl && !params.name && !params.baseRef ? await __ocResolveSpawnParentRepositoryWorkspace(params.inheritParentKey, lifecycleTarget.agentId, { signal }) : void 0;
\tif (repositoryParentSource) {
\t\tconst preparedRepository = await __ocPrepareSpawnChildRepositoryWorkspace({
\t\t\tsource: repositoryParentSource,
\t\t\ttarget: lifecycleTarget,
\t\t\tsignal,
\t\t\tcommitGuard
\t\t});
\t\tif (!preparedRepository.ok) return preparedRepository;
\t\treturn ok({
\t\t\trepositoryWorkspaceId: preparedRepository.value.repositoryWorkspaceId,
\t\t\t...preparedRepository.value.rollback ? { rollback: preparedRepository.value.rollback } : {}
\t\t});
\t}
${inheritedLine}`;

worktreeSource = worktreeSource.replace(inheritedLine, repositoryBranch);

fs.chmodSync(worktreePath, 0o644);
fs.writeFileSync(worktreePath, worktreeSource);
fs.chmodSync(worktreePath, 0o444);

// Prove the built artifact, not just the intent: the rewritten file must import
// the services it calls, carry the guarded branch, and keep the worktree route.
const built = fs.readFileSync(worktreePath, "utf8");
const requiredBuiltLines = [
  `import { ${forkAlias} as __ocForkSessionRepositoryWorkspace } from "./${forkFile}";`,
  `import { ${repositoryStoreAlias} as __ocGetSessionRepositoryWorkspaceStore } from "./${repositoryStoreFile}";`,
  "async function __ocResolveSpawnParentRepositoryWorkspace(",
  "async function __ocPrepareSpawnChildRepositoryWorkspace(",
  "const repositoryParentSource = params.inheritParentKey",
  "await __ocForkSessionRepositoryWorkspace({",
  "const inheritedSource = params.inheritParentKey",
];
for (const line of requiredBuiltLines) {
  if (!built.includes(line)) fail(`repository-parent spawn branch: built output lost ${line}`);
}
for (const target of [forkFile, repositoryStoreFile]) {
  if (!fs.existsSync(path.join(dist, target))) fail(`repository-parent spawn branch: missing module ${target}`);
}
console.log(`repository-parent spawn: patched ${worktreeFile}; fork ${forkFile}; store ${repositoryStoreFile}`);
