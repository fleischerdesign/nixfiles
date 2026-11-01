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
