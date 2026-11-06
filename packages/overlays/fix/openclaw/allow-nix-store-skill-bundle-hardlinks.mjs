#!/usr/bin/env node
// Local patch for openclaw-gateway: let the worker skill bundler read immutable
// Nix-store skill trees.
//
// Why this exists: `auto-optimise-store` hardlinks identical files across store
// outputs, so every packaged `SKILL.md` has nlink > 1. The skill bundle reader
// used for worker turns hardcodes `hardlinks: "reject"` and fails with
// INVALID_BUNDLE before any model call, while ordinary skill discovery already
// trusts immutable store roots. See docs/operations.md.
//
// The transform is anchored by symbols and option names, never by file name or
// line number: dist chunk names change every release. When an anchor disappears
// the build fails and names the overlay to delete - silently shipping an
// unpatched gateway is the one outcome this script must not produce.

import fs from "node:fs";
import path from "node:path";

const TAG = "openclaw skill-bundle hardlink patch";
const POLICY_MARKER = "function shouldRejectHardlinkedPluginFiles";
const READER_MARKER = "async function readSkillBundleTree";
const LOCAL_ALIAS = "__nixfilesShouldRejectHardlinkedSkillTree";
// Unique to the tree reader: the published-manifest read in the same module uses
// `symlinks: "reject"` and `maxBytes: file.sizeBytes`.
const READ_CALL = /hardlinks: "reject",(\s*)symlinks,(\s*)maxBytes: SKILL_LIBRARY_MAX_FILE_BYTES/g;

function fail(message) {
  console.error(`${TAG}: ${message}`);
  process.exit(1);
}

function occurrences(haystack, needle) {
  return haystack.split(needle).length - 1;
}

const root = process.argv[2] ?? process.env.OPENCLAW_PACKAGE_ROOT;
if (!root) fail("pass the installed package root as the first argument");
const distDir = path.join(root, "dist");
if (!fs.existsSync(distDir)) fail(`dist directory missing under ${root}`);

const modules = new Map(
  fs
    .readdirSync(distDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && /\.m?js$/.test(entry.name))
    .map((entry) => [entry.name, fs.readFileSync(path.join(distDir, entry.name), "utf8")]),
);

const findUnique = (marker, label) => {
  const hits = [...modules].filter(([, source]) => source.includes(marker));
  if (hits.length !== 1) fail(`expected exactly one module containing ${label}, found ${hits.length}`);
  return hits[0];
};

const [policyName, policySource] = findUnique(POLICY_MARKER, "the plugin hardlink policy");
const [readerName, readerSource] = findUnique(READER_MARKER, "the skill bundle reader");

if (readerSource.includes(LOCAL_ALIAS)) {
  fail(
    "the package already carries this patch - upstream fixed the skill bundle reader. " +
      "Delete packages/overlays/fix/openclaw and its entry in flake.nix.",
  );
}

// The policy chunk exports the predicate under a short local alias; read it from
// the module instead of assuming a name that changes between releases.
const exportMatch = policySource.match(
  /export \{ shouldRejectHardlinkedPluginFiles as (\w+) \};/,
);
if (!exportMatch) fail(`${policyName} no longer exports shouldRejectHardlinkedPluginFiles; the policy moved`);

const matches = [...readerSource.matchAll(READ_CALL)];
if (matches.length !== 1) {
  fail(
    `expected exactly one hardlink-rejecting skill tree read in ${readerName}, found ${matches.length} - ` +
      "upstream changed how the bundle reader admits files",
  );
}

const policyImport = `import { ${exportMatch[1]} as ${LOCAL_ALIAS} } from "./${policyName}";\n`;
const patchedReader = readerSource
  .replace(
    READ_CALL,
    (_match, gapOne, gapTwo) =>
      `hardlinks: ${LOCAL_ALIAS}({ origin: "config", rootDir: directory, env: process.env }) ` +
      `? "reject" : "allow",${gapOne}symlinks,${gapTwo}maxBytes: SKILL_LIBRARY_MAX_FILE_BYTES`,
  )
  .replace(/^/, policyImport);

if (!patchedReader.includes(LOCAL_ALIAS) || !patchedReader.includes(policyImport)) {
  fail("the transform did not produce the expected module; refusing to write a partial patch");
}

fs.writeFileSync(path.join(distDir, readerName), patchedReader);
console.log(`${TAG}: ${readerName} now trusts immutable store skill trees (policy: ${policyName})`);
