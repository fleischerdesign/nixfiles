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
  console.error(`openclaw dist patch: ${message}`);
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
if (source.includes("__ocResourceHardlinkPolicy")) fail("skill bundle already patched");

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

// ---------------------------------------------------------------------------
// Repository-parent spawn branch.
//
// A visible `sessions_spawn` with a cloud placement profile forces
// `worktree: true` and carries no repository selector. A parent whose workspace
// is a session repository workspace (the New Chat -> GitHub flow) therefore has
// no project id or managed worktree to inherit, and the child falls back to the
// Gateway's default agent workspace: the wrong repository.
//
// The child must start from the parent's *live* working tree, not the checkpoint
// accepted at the end of the parent's previous turn. The gateway-side commit
// model only accepts a workspace after a turn returns, so a fork of the accepted
// checkpoint is one turn behind. This patch adds a read-only capture that runs
// under the parent's existing placement turn claim, through the same tunnel,
// quiesce and reconcile primitives the turn-end path uses:
//
//   workspaceOperations.run -> resolve workspace -> start tunnel -> quiesce ->
//   reconcile (live upload + stability fence) -> stage the child checkpoint ->
//   verify final double manifests -> publish child -> resume quiescence.
//
// It never claims, accepts or releases the parent's turn claim and never mutates
// the parent's accepted checkpoint or revision. On a shared host the quiesce does
// not freeze processes; the final fence therefore requires the remote manifest to
// be identical across two captures or fails explicitly instead of producing an
// atomic-looking snapshot that is not stable.

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

const placementFile = findOne(
  "worker placement runtime",
  (source) =>
    source.includes("function createRepositoryWorkspaceMutationService(options) {") &&
    source.includes("repositoryWorkspaceMutationService: createRepositoryWorkspaceMutationService({"),
);

const createFile = findOne(
  "sessions create handler",
  (source) =>
    source.includes("let prepareLifecycle;") &&
    source.includes("prepareLifecycle = async (lifecycleTarget) => {") &&
    source.includes("const prepared = await prepareSessionWorktreeCreation({"),
);

// ---- 1. Fork accepts a live stager instead of copying the accepted checkpoint ----
const forkPath = path.join(dist, forkFile);
let forkSource = fs.readFileSync(forkPath, "utf8");
if (forkSource.includes("__ocStageForkWorkspace")) fail("repository fork stage support is already patched");
const forkCheckpointAnchor = "\t\tif (source.checkpointRef) target = await withSessionRepositoryCheckpoint({";
if (forkSource.split(forkCheckpointAnchor).length - 1 !== 1) {
  fail("repository fork: checkpoint anchor moved");
}
forkSource = forkSource.replace(
  forkCheckpointAnchor,
  `\t\tif (params.stage) {
\t\t\tif (!source.baseCommit || !source.baseManifestHash) throw new Error("Repository checkpoint capture requires a pinned base");
\t\t\tawait params.stage({ target, source });
\t\t\tassertCurrent();
\t\t\ttarget = await store.get(target.workspaceId) ?? target;
\t\t} else if (source.checkpointRef) target = await withSessionRepositoryCheckpoint({`,
);
fs.chmodSync(forkPath, 0o644);
fs.writeFileSync(forkPath, forkSource);
fs.chmodSync(forkPath, 0o444);

// ---- 2. Read-only capture under the parent's existing turn claim ----
const placementPath = path.join(dist, placementFile);
let placementSource = fs.readFileSync(placementPath, "utf8");
if (placementSource.includes("__ocCaptureRepositoryWorkspaceForFork")) {
  fail("repository capture support is already patched");
}

const captureAnchor = "function createRepositoryWorkspaceMutationService(options) {";
if (placementSource.split(captureAnchor).length - 1 !== 1) {
  fail("repository capture: service anchor moved");
}
const captureFunction = `/**
 * Capture the parent's live repository workspace into an already created child
 * workspace, under the parent placement's existing turn claim. Read-only for the
 * parent: no claim, acceptance, checkpoint or revision is written there.
 */
async function __ocCaptureRepositoryWorkspaceForFork(deps, params) {
	const { placements, environments, workspaceOperations, resolveWorkspace } = deps;
	const placement = await placements.getAsync(params.sessionId);
	params.assertCurrent();
	if (placement?.state !== "active" || placement.agentId !== params.agentId || placement.sessionKey !== params.sessionKey) throw new Error("Repository workspace capture requires the parent session's active cloud placement");
	const turnClaim = projectWorkerSessionTurnClaim(placement);
	if (!turnClaim) throw new Error("Repository workspace capture requires the parent turn to hold its placement claim; retry from the running turn");
	const environment = environments.get(placement.environmentId);
	if (!isCurrentActiveWorkerEnvironment(placement, environment)) throw new Error("Repository workspace capture environment is no longer current");
	const assertPlacementCurrent = () => {
		params.assertCurrent();
		const current = placements.get(params.sessionId);
		const currentEnvironment = environments.get(placement.environmentId);
		if (current?.state !== "active" || current.agentId !== placement.agentId || current.sessionKey !== placement.sessionKey || current.generation !== placement.generation || current.environmentId !== placement.environmentId || current.activeOwnerEpoch !== placement.activeOwnerEpoch || current.remoteWorkspaceDir !== placement.remoteWorkspaceDir || !isCurrentActiveWorkerEnvironment(current, currentEnvironment) || currentEnvironment?.leaseId !== environment?.leaseId || !placements.validateTurnClaim(turnClaim)) throw new Error("Parent repository workspace authority changed during capture; retry from the parent's current turn");
	};
	return await workspaceOperations.run(placement.environmentId, async () => {
		assertPlacementCurrent();
		const workspace = await resolveWorkspace(params);
		if (workspace.kind !== "repository" || workspace.repository.workspaceId !== params.sourceWorkspaceId) throw new Error("Parent session no longer owns its cloud repository workspace");
		if (!workspace.repository.baseCommit || !workspace.repository.baseManifestHash) throw new Error("Parent repository workspace has no pinned base");
		assertPlacementCurrent();
		const tunnel = await environments.startTunnel({
			environmentId: placement.environmentId,
			ownerEpoch: placement.activeOwnerEpoch
		});
		assertPlacementCurrent();
		if (tunnel.environmentId !== placement.environmentId || tunnel.ownerEpoch !== placement.activeOwnerEpoch) throw new Error("Repository workspace capture tunnel owner changed");
		const quiescence = await tunnel.quiesceWorkspace(placement.remoteWorkspaceDir);
		try {
			assertPlacementCurrent();
			const reconciliation = await tunnel.reconcileWorkspace({
				remoteWorkspaceDir: placement.remoteWorkspaceDir,
				baseManifestRef: workspace.repository.baseManifestHash,
				source: {
					kind: "repository",
					authorize: assertPlacementCurrent,
					referenceManifestRef: workspace.repository.manifestHash ?? workspace.repository.baseManifestHash,
					prepareCheckpoint: async (payload) => {
						const prepared = await stageSessionRepositoryCheckpoint({
							...payload,
							workspaceId: params.target.workspaceId,
							expectedRevision: params.target.expectedRevision,
							assertCurrent: assertPlacementCurrent
						});
						return {
							verify: prepared.verify,
							discard: prepared.discard,
							publish: async () => {
								const accepted = await prepared.publish();
								assertPlacementCurrent();
								return accepted;
							}
						};
					}
				}
			});
			await verifyReconciledWorkspaceFinal(reconciliation, quiescence);
			assertPlacementCurrent();
			return {
				manifestRef: reconciliation.manifestRef,
				changed: reconciliation.changed === true
			};
		} finally {
			await quiescence.resume();
		}
	});
}
${captureAnchor}`;
placementSource = placementSource.replace(captureAnchor, captureFunction);

const serviceReturnAnchor = "\treturn { async mutate(params) {";
if (placementSource.split(serviceReturnAnchor).length - 1 !== 1) {
  fail("repository capture: mutation service return anchor moved");
}
placementSource = placementSource.replace(
  serviceReturnAnchor,
  `\treturn {
\t\tasync captureForFork(params) {
\t\t\treturn await __ocCaptureRepositoryWorkspaceForFork({
\t\t\t\tplacements,
\t\t\t\tenvironments,
\t\t\t\tworkspaceOperations: options.workspaceOperations,
\t\t\t\tresolveWorkspace: options.resolveWorkspace
\t\t\t}, params);
\t\t},
\t\tasync mutate(params) {`,
);

const exportAnchor = "export { createGatewayGitHubPublicationRuntime, createGatewayWorkerPlacementRuntime };";
if (placementSource.split(exportAnchor).length - 1 !== 1) {
  fail("repository capture: export anchor moved");
}
placementSource = placementSource.replace(
  exportAnchor,
  "export { createGatewayGitHubPublicationRuntime, createGatewayWorkerPlacementRuntime, __ocCaptureRepositoryWorkspaceForFork };",
);
fs.chmodSync(placementPath, 0o644);
fs.writeFileSync(placementPath, placementSource);
fs.chmodSync(placementPath, 0o444);

// ---- 3. Prepare a child for a visible placed spawn from a repository parent ----
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
	const parent = options.parent ?? loadGatewaySessionEntryReadOnly(parentSessionKey, { agentId });
	const repositoryWorkspaceId = normalizeOptionalString(parent.entry?.repositoryWorkspaceId);
	if (!repositoryWorkspaceId || parent.entry?.worktree) return;
	if (!parent.entry?.sessionId) return;
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
		sessionId: parent.entry.sessionId,
		workspaceId: repositoryWorkspaceId,
		assertParentCurrent
	};
}
/** Capture the parent's live tree into an isolated child workspace. */
async function __ocPrepareSpawnChildRepositoryWorkspace(params) {
	const repositories = __ocGetSessionRepositoryWorkspaceStore();
	const source = params.source;
	const capture = params.capture;
	const assertCurrent = () => {
		params.signal?.throwIfAborted();
		params.commitGuard();
		source.assertParentCurrent();
	};
	const assertTargetOwner = async (workspaceId) => {
		const target = await repositories.get(workspaceId);
		if (!target) return false;
		if (target.agentId !== params.target.agentId || target.sessionKey !== params.target.key) throw new Error("Spawn child repository workspace changed owner; refusing cleanup");
		return true;
	};
	const deleteTarget = async (workspaceId) => {
		if (!(await assertTargetOwner(workspaceId))) return;
		await repositories.delete({
			workspaceId,
			assertCurrent: () => {}
		});
	};
	// A failed attempt may have published a checkpoint into an existing target.
	// That accepted orphan would make every retry refuse, so remove it. A
	// pre-existing target that this attempt did not mutate stays untouched.
	const cleanupFailedTarget = async (workspaceId, created) => {
		try {
			const current = await repositories.get(workspaceId);
			if (!current || current.agentId !== params.target.agentId || current.sessionKey !== params.target.key) return;
			if (!created && !current.checkpointRef) return;
			await repositories.delete({
				workspaceId,
				assertCurrent: () => {}
			});
		} catch {
			// Never mask the failure that triggered cleanup.
		}
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
	if (!workspace.baseCommit || !workspace.baseManifestHash) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn parent repository has no pinned base; let the parent finish a turn and retry"));
	assertCurrent();
	let target;
	let created = false;
	if (existing) {
		if (existing.url !== workspace.url || existing.baseCommit !== workspace.baseCommit || existing.baseManifestHash !== workspace.baseManifestHash) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn child repository workspace does not match its parent; delete the child session and retry"));
		if (existing.checkpointRef) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn child repository workspace already has an accepted checkpoint; delete the child session and retry"));
		target = existing;
	} else {
		if (!capture) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn parent repository needs a live workspace capture service; retry from a visible placed session"));
		try {
			target = await __ocForkSessionRepositoryWorkspace({
				store: repositories,
				sourceWorkspaceId: source.workspaceId,
				agentId: params.target.agentId,
				sessionKey: params.target.key,
				assertCurrent,
				stage: async ({ target: child }) => {
					created = true;
					target = child;
					await capture.captureForFork({
						sessionId: source.sessionId,
						sessionKey: source.parentKey,
						agentId: params.target.agentId,
						sourceWorkspaceId: source.workspaceId,
						target: {
							workspaceId: child.workspaceId,
							expectedRevision: child.revision
						},
						signal: params.signal,
						assertCurrent
					});
				}
			});
			created = true;
		} catch (error) {
			if (target) await cleanupFailedTarget(target.workspaceId, true);
			if (collectNestedErrorCandidates(error).some((cause) => cause instanceof SessionWorktreeSourceChangedError)) throw error;
			return err(errorShape(ErrorCodes.UNAVAILABLE, formatErrorMessage(error)));
		}
	}
	if (!target.checkpointRef) {
		if (!capture) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn parent repository needs a live workspace capture service; retry from a visible placed session"));
		try {
			await capture.captureForFork({
				sessionId: source.sessionId,
				sessionKey: source.parentKey,
				agentId: params.target.agentId,
				sourceWorkspaceId: source.workspaceId,
				target: {
					workspaceId: target.workspaceId,
					expectedRevision: target.revision
				},
				signal: params.signal,
				assertCurrent
			});
			target = await repositories.get(target.workspaceId) ?? target;
		} catch (error) {
			await cleanupFailedTarget(target.workspaceId, created);
			if (collectNestedErrorCandidates(error).some((cause) => cause instanceof SessionWorktreeSourceChangedError)) throw error;
			return err(errorShape(ErrorCodes.UNAVAILABLE, formatErrorMessage(error)));
		}
	}
	try {
		assertCurrent();
	} catch (error) {
		await cleanupFailedTarget(target.workspaceId, created);
		throw error;
	}
	return ok({
		repositoryWorkspaceId: target.workspaceId,
		rollback: async () => await deleteTarget(target.workspaceId)
	});
}
${helperAnchor}`;

worktreeSource = worktreeSource.replace(helperAnchor, helpers);

const hiddenGuardAnchor =
  '\tconst inheritedSource = params.inheritParentKey && !acceptedWorktree && !acceptedPending ? await resolveSpawnParentWorktreeSource(params.inheritParentKey, lifecycleTarget.agentId, { signal }) : void 0;';
if (worktreeSource.split(hiddenGuardAnchor).length - 1 !== 1) {
  fail("repository-parent spawn branch: inherited branch anchor moved");
}
const hiddenGuard = `\tconst inheritedRepositoryParent = params.inheritParentKey && !acceptedWorktree && !acceptedPending ? loadGatewaySessionEntryReadOnly(params.inheritParentKey, { agentId: lifecycleTarget.agentId }) : void 0;
\tconst isRepositoryParent = Boolean(inheritedRepositoryParent?.entry?.repositoryWorkspaceId && inheritedRepositoryParent.entry.sessionId && !inheritedRepositoryParent.entry.worktree);
\tif (isRepositoryParent && !params.workspace && !params.projectGitUrl) {
\t\tif (params.name || params.baseRef) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn from a repository workspace cannot use an explicit worktree name or baseRef; omit it to inherit the parent's live tree."));
\t\tif (!params.repositoryParentInheritance) return err(errorShape(ErrorCodes.UNAVAILABLE, "Spawn from a repository workspace requires the visible placed session path; hidden subagents cannot inherit it. Spawn with visible=true and a placement profile."));
\t}
\tconst repositoryParentSource = isRepositoryParent && params.repositoryParentInheritance && !params.workspace && !params.projectGitUrl ? await __ocResolveSpawnParentRepositoryWorkspace(params.inheritParentKey, lifecycleTarget.agentId, {
\t\tsignal,
\t\tparent: inheritedRepositoryParent
\t}) : void 0;
\tif (repositoryParentSource) {
\t\tconst preparedRepository = await __ocPrepareSpawnChildRepositoryWorkspace({
\t\t\tsource: repositoryParentSource,
\t\t\tcapture: params.repositoryCaptureService,
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
${hiddenGuardAnchor}`;
worktreeSource = worktreeSource.replace(hiddenGuardAnchor, hiddenGuard);
fs.chmodSync(worktreePath, 0o644);
fs.writeFileSync(worktreePath, worktreeSource);
fs.chmodSync(worktreePath, 0o444);

// ---- 4. Pass the coordinator service from the visible placed create path ----
const createPath = path.join(dist, createFile);
let createSource = fs.readFileSync(createPath, "utf8");
if (createSource.includes("repositoryParentInheritance")) fail("visible repository-parent wiring is already patched");
const createAnchor = "\t\t\t\t\trunSetupScript: clientScopes.includes(ADMIN_SCOPE),";
if (createSource.split(createAnchor).length - 1 !== 1) {
  fail("visible repository-parent wiring: prepare call anchor moved");
}
createSource = createSource.replace(
  createAnchor,
  `\t\t\t\t\trepositoryParentInheritance: true,
\t\t\t\t\trepositoryCaptureService: context.workerRepositoryWorkspaceMutationService,
\t\t\t\t\trunSetupScript: clientScopes.includes(ADMIN_SCOPE),`,
);
fs.chmodSync(createPath, 0o644);
fs.writeFileSync(createPath, createSource);
fs.chmodSync(createPath, 0o444);

// Prove the built artifacts, not just the intent.
const worktreeBuilt = fs.readFileSync(worktreePath, "utf8");
const placementBuilt = fs.readFileSync(placementPath, "utf8");
const createBuilt = fs.readFileSync(createPath, "utf8");
const forkBuilt = fs.readFileSync(forkPath, "utf8");
const required = [
  [worktreeBuilt, `import { ${forkAlias} as __ocForkSessionRepositoryWorkspace } from "./${forkFile}";`],
  [worktreeBuilt, `import { ${repositoryStoreAlias} as __ocGetSessionRepositoryWorkspaceStore } from "./${repositoryStoreFile}";`],
  [worktreeBuilt, "async function __ocResolveSpawnParentRepositoryWorkspace("],
  [worktreeBuilt, "async function __ocPrepareSpawnChildRepositoryWorkspace("],
  [worktreeBuilt, "const isRepositoryParent = Boolean(inheritedRepositoryParent?.entry?.repositoryWorkspaceId"],
  [worktreeBuilt, "Spawn from a repository workspace cannot use an explicit worktree name or baseRef"],
  [worktreeBuilt, "const repositoryParentSource = isRepositoryParent && params.repositoryParentInheritance"],
  [worktreeBuilt, "capture: params.repositoryCaptureService"],
  [worktreeBuilt, "hidden subagents cannot inherit it"],
  [worktreeBuilt, "const cleanupFailedTarget = async (workspaceId, created) => {"],
  [placementBuilt, "async function __ocCaptureRepositoryWorkspaceForFork(deps, params) {"],
  [placementBuilt, "return {\n\t\tasync captureForFork(params) {"],
  [placementBuilt, "captureForFork(params) {"],
  [placementBuilt, "verifyReconciledWorkspaceFinal(reconciliation, quiescence);"],
  [placementBuilt, "validateTurnClaim(turnClaim)"],
  [placementBuilt, "await quiescence.resume();"],
  [placementBuilt, "__ocCaptureRepositoryWorkspaceForFork };"],
  [forkBuilt, "if (params.stage) {"],
  [createBuilt, "repositoryParentInheritance: true,"],
  [createBuilt, "repositoryCaptureService: context.workerRepositoryWorkspaceMutationService,"],
];
for (const [built, line] of required) {
  if (!built.includes(line)) fail(`repository-parent spawn branch: built output lost ${line}`);
}
for (const target of [forkFile, repositoryStoreFile]) {
  if (!fs.existsSync(path.join(dist, target))) fail(`repository-parent spawn branch: missing module ${target}`);
}
console.log(
  `repository-parent spawn: patched ${worktreeFile}, ${placementFile}, ${createFile}; fork ${forkFile}; store ${repositoryStoreFile}`,
);

// ---------------------------------------------------------------------------
// Worker-tool spawn on a paired node.
//
// The reduced `sessions_spawn` tool a placed worker sees has no placement
// selector, by design: its closed schema accepts only task, label, agentId,
// model and runTimeoutSeconds. The child must therefore run on the node that
// already hosts the authenticated parent environment - the same node the
// parent turn's placement was admitted for - never on the Gateway's default
// cloud provider. The old dispatch call passed only the parent's profile id
// and snapshot, so a repository child fell into the cloud path and failed with
// "Repository cloud sessions require a managed-node cloud provider or paired
// node".
//
// This branch derives the node id from the parent environment record (not from
// model-supplied arguments), validates it against the normal device placement
// destination, and takes the runtime requirement from the child session's own
// capabilities. Only a `device` provider requests a device placement: a
// managed cloud provider that also carries a nodeDeviceId keeps its old cloud
// route. Dispatch failure handling is unchanged.

const workerExecutorFile = findOne(
  "worker session tool executor",
  (source) => source.includes("function createWorkerSessionToolExecutor(params, definitions) {"),
);
const destinationFile = findOne(
  "worker placement destination",
  (source) => source.includes("function resolveWorkerPlacementDestination(params) {"),
);
const sessionRuntimeFile = findOne(
  "worker placement session runtime",
  (source) => source.includes("function resolveWorkerPlacementSessionRuntimeCapabilities(params) {"),
);
function exportAlias(file, exportedName) {
  const alias = new RegExp(`export\\s*\\{[^}]*\\b${exportedName}\\s+as\\s+([A-Za-z0-9_$]+)`, "u").exec(
    fs.readFileSync(path.join(dist, file), "utf8"),
  )?.[1];
  if (!alias) fail(`worker node spawn: export alias missing for ${exportedName} in ${file}`);
  return alias;
}
const destinationAlias = exportAlias(destinationFile, "resolveWorkerPlacementDestination");
const sessionRuntimeAlias = exportAlias(sessionRuntimeFile, "resolveWorkerPlacementSessionRuntimeCapabilities");

const workerExecutorPath = path.join(dist, workerExecutorFile);
let workerExecutorSource = fs.readFileSync(workerExecutorPath, "utf8");
if (workerExecutorSource.includes("__ocBuildWorkerChildDispatchRequest")) {
  fail("worker node spawn: child dispatch request builder is already patched");
}

const workerImportAnchor = 'import { Value } from "typebox/value";';
if (workerExecutorSource.split(workerImportAnchor).length - 1 !== 1) {
  fail("worker node spawn: import anchor moved");
}
workerExecutorSource = workerExecutorSource.replace(
  workerImportAnchor,
  `${workerImportAnchor}\nimport { ${destinationAlias} as __ocResolveWorkerPlacementDestination } from "./${destinationFile}";\nimport { ${sessionRuntimeAlias} as __ocResolveWorkerPlacementSessionRuntimeCapabilities } from "./${sessionRuntimeFile}";`,
);

const workerHelperAnchor = "function createWorkerSessionToolExecutor(params, definitions) {";
if (workerExecutorSource.split(workerHelperAnchor).length - 1 !== 1) {
  fail("worker node spawn: executor anchor moved");
}
const workerHelpers = `/** Build the child dispatch request from the authenticated parent environment. */
function __ocBuildWorkerChildDispatchRequest(params) {
	const { cfg, sourceEnvironment, sessionId, sessionKey, agentId, entry } = params;
	if (sourceEnvironment.providerId !== "device") return {
		sessionId,
		sessionKey,
		agentId,
		profileId: sourceEnvironment.profileId,
		executionMode: "worker-turn",
		inheritedProfile: {
			providerId: sourceEnvironment.providerId,
			profileSnapshot: sourceEnvironment.profileSnapshot
		}
	};
	const nodeDeviceId = normalizeOptionalString(sourceEnvironment.nodeDeviceId);
	if (!nodeDeviceId) throw new Error("Parent device placement has no node id; refusing to spawn from it");
	if (sourceEnvironment.providerId !== "device" || sourceEnvironment.profileId !== \`device:\${nodeDeviceId}\` || !isRecord(sourceEnvironment.profileSnapshot?.settings) || sourceEnvironment.profileSnapshot.settings.device !== nodeDeviceId) throw new Error("Parent node placement identity is inconsistent; refusing to spawn from it");
	const destination = __ocResolveWorkerPlacementDestination({
		cfg,
		deviceId: nodeDeviceId
	});
	if (!destination.ok || !destination.value || destination.value.deviceId !== nodeDeviceId || destination.value.profileId !== \`device:\${nodeDeviceId}\`) throw new Error("Parent node placement cannot be resolved for the spawn child");
	const capabilities = __ocResolveWorkerPlacementSessionRuntimeCapabilities({
		cfg,
		entry,
		agentId,
		sessionKey
	});
	if (capabilities.executionMode !== "worker-turn" || !capabilities.devicePlacement) throw new Error("Spawn child runtime cannot run on the parent's paired node");
	return {
		sessionId,
		sessionKey,
		agentId,
		profileId: sourceEnvironment.profileId,
		executionMode: "worker-turn",
		inheritedProfile: {
			providerId: sourceEnvironment.providerId,
			profileSnapshot: sourceEnvironment.profileSnapshot
		},
		deviceId: nodeDeviceId,
		devicePlacement: capabilities.devicePlacement
	};
}
${workerHelperAnchor}`;
workerExecutorSource = workerExecutorSource.replace(workerHelperAnchor, workerHelpers);

const dispatchAnchor = `\t\t\t\t\t\tif (childPlacement?.state !== "active") try {
\t\t\t\t\t\t\tawait params.dispatchChild({
\t\t\t\t\t\t\t\tsessionId: childSessionId,
\t\t\t\t\t\t\t\tsessionKey: operation.childSessionKey,
\t\t\t\t\t\t\t\tagentId: targetAgentId,
\t\t\t\t\t\t\t\tprofileId: sourceEnvironment.profileId,
\t\t\t\t\t\t\t\texecutionMode: "worker-turn",
\t\t\t\t\t\t\t\tinheritedProfile: {
\t\t\t\t\t\t\t\t\tproviderId: sourceEnvironment.providerId,
\t\t\t\t\t\t\t\t\tprofileSnapshot: sourceEnvironment.profileSnapshot
\t\t\t\t\t\t\t\t}
\t\t\t\t\t\t\t}, void 0, assertSource);
\t\t\t\t\t\t} catch (error) {
\t\t\t\t\t\t\ttry {
\t\t\t\t\t\t\t\tassertActiveChildPlacement();
\t\t\t\t\t\t\t} catch {
\t\t\t\t\t\t\t\tthrow new WorkerSessionToolOutcomeUnknownError(error);
\t\t\t\t\t\t\t}
\t\t\t\t\t\t}`;
if (workerExecutorSource.split(dispatchAnchor).length - 1 !== 1) {
  fail("worker node spawn: dispatch call anchor moved");
}
const dispatchReplacement = `\t\t\t\t\t\tif (childPlacement?.state !== "active") try {
\t\t\t\t\t\t\tawait params.dispatchChild(__ocBuildWorkerChildDispatchRequest({
\t\t\t\t\t\t\t\tcfg: getRuntimeConfig(),
\t\t\t\t\t\t\t\tsourceEnvironment,
\t\t\t\t\t\t\t\tsessionId: childSessionId,
\t\t\t\t\t\t\t\tsessionKey: operation.childSessionKey,
\t\t\t\t\t\t\t\tagentId: targetAgentId,
\t\t\t\t\t\t\t\tentry: loaded.entry
\t\t\t\t\t\t\t}), void 0, assertSource);
\t\t\t\t\t\t} catch (error) {
\t\t\t\t\t\t\ttry {
\t\t\t\t\t\t\t\tassertActiveChildPlacement();
\t\t\t\t\t\t\t} catch {
\t\t\t\t\t\t\t\tthrow new WorkerSessionToolOutcomeUnknownError(error);
\t\t\t\t\t\t\t}
\t\t\t\t\t\t}`;
workerExecutorSource = workerExecutorSource.replace(dispatchAnchor, dispatchReplacement);

const workerExportAnchor =
  "export { createWorkerGatewayTools, createWorkerSessionToolExecutor, createWorkerWorkshopCallRetention };";
if (workerExecutorSource.split(workerExportAnchor).length - 1 !== 1) {
  fail("worker node spawn: export anchor moved");
}
workerExecutorSource = workerExecutorSource.replace(
  workerExportAnchor,
  "export { createWorkerGatewayTools, createWorkerSessionToolExecutor, createWorkerWorkshopCallRetention, __ocBuildWorkerChildDispatchRequest };",
);
fs.chmodSync(workerExecutorPath, 0o644);
fs.writeFileSync(workerExecutorPath, workerExecutorSource);
fs.chmodSync(workerExecutorPath, 0o444);

const workerBuilt = fs.readFileSync(workerExecutorPath, "utf8");
for (const line of [
  'import { ' + destinationAlias + ' as __ocResolveWorkerPlacementDestination } from "./' + destinationFile + '";',
  'import { ' + sessionRuntimeAlias + ' as __ocResolveWorkerPlacementSessionRuntimeCapabilities } from "./' + sessionRuntimeFile + '";',
  "function __ocBuildWorkerChildDispatchRequest(params) {",
  "devicePlacement: capabilities.devicePlacement",
  "await params.dispatchChild(__ocBuildWorkerChildDispatchRequest({",
  "__ocBuildWorkerChildDispatchRequest };",
]) {
  if (!workerBuilt.includes(line)) fail(`worker node spawn: built output lost ${line}`);
}
console.log(`worker node spawn: patched ${workerExecutorFile}`);
