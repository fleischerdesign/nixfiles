#!/usr/bin/env node
// Refuse a managed child worktree inherited from a repository-only session.
//
// A worker session created from a GitHub repository keeps its checkout on the
// paired node; the Gateway has only the publication donor. `inheritParentKey`
// currently ignores `repositoryWorkspaceId`, so `prepareSessionWorktreeCreation`
// falls back to the agent workspace and base-ref discovery runs
// `git ls-remote origin` in an unrelated repository. It failed there (no origin);
// with a remote it would have created a worktree of the wrong repository.
//
// This step runs after the skill hardlink patch, installs the decision module and
// adds one guard before the inherited source is resolved. It fails the build when
// the bundle shape moves, so a release bump cannot ship an unpatched package.
import fs from "node:fs";
import path from "node:path";

function fail(message) {
  console.error(`node spawn source: ${message}`);
  process.exit(1);
}

const root = process.env.OPENCLAW_PACKAGE_ROOT;
if (!root) fail("OPENCLAW_PACKAGE_ROOT is required");
const dist = path.join(root, "dist");
if (!fs.existsSync(dist)) fail(`dist directory missing: ${dist}`);

const policySource = process.env.OPENCLAW_NODE_SPAWN_SOURCE_POLICY;
if (!policySource || !fs.existsSync(policySource)) {
  fail(`policy module missing: ${policySource ?? "(unset)"}`);
}

const marker = "async function prepareSessionWorktreeCreation(";
const anchorText = "const inheritedSource = params.inheritParentKey";
const owners = fs
  .readdirSync(dist, { withFileTypes: true })
  .filter((entry) => (entry.isFile() || entry.isSymbolicLink()) && /\.m?js$/.test(entry.name))
  .filter((entry) => {
    const source = fs.readFileSync(path.join(dist, entry.name), "utf8");
    return (
      source.includes(marker) &&
      source.includes(anchorText) &&
      source.includes("loadGatewaySessionEntryReadOnly")
    );
  });
if (owners.length !== 1) fail(`expected exactly one spawn preparation chunk, found ${owners.length}`);

const file = path.join(dist, owners[0].name);
let source = fs.readFileSync(file, "utf8");

const importLine =
  'import { parentSpawnSourceRefusal as __ocNodeSpawnSourcePolicy } from "./nix-node-spawn-source-policy.mjs";';
if (source.includes("__ocNodeSpawnSourcePolicy")) fail("spawn source already patched");

for (const dependency of [
  "t as err",
  "d as errorShape",
  "t as ErrorCodes",
  "i as loadGatewaySessionEntryReadOnly",
]) {
  if (!source.includes(dependency)) fail(`bundle no longer imports ${dependency}`);
}

const anchorIndex = source.indexOf(anchorText);
if (anchorIndex < 0 || source.indexOf(anchorText, anchorIndex + anchorText.length) >= 0) {
  fail("expected one inherited-source assignment");
}
const lineStart = source.lastIndexOf("\n", anchorIndex) + 1;

const guard =
  "\tif (params.inheritParentKey && !acceptedWorktree && !acceptedPending && !params.workspace && !params.projectGitUrl) {\n" +
  "\t\tconst parent = loadGatewaySessionEntryReadOnly(params.inheritParentKey, { agentId: lifecycleTarget.agentId });\n" +
  "\t\tconst refusal = __ocNodeSpawnSourcePolicy(parent.entry);\n" +
  "\t\tif (refusal) return err(errorShape(ErrorCodes.UNAVAILABLE, refusal));\n" +
  "\t}\n";

source = `${importLine}\n${source.slice(0, lineStart)}${guard}${source.slice(lineStart)}`;

const policyTarget = path.join(dist, "nix-node-spawn-source-policy.mjs");
fs.copyFileSync(policySource, policyTarget);
fs.chmodSync(policyTarget, 0o444);
// The npm cache may hand back read-only files; write, then restore the package mode.
fs.chmodSync(file, 0o644);
fs.writeFileSync(file, source);
fs.chmodSync(file, 0o444);
console.log(`node spawn source: patched ${owners[0].name} and installed ${path.basename(policyTarget)}`);
