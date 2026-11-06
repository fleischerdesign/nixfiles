#!/usr/bin/env node
// Local patch for openclaw-gateway: prepare session capability reads for a
// worker turn.
//
// Why this exists: a session placed on a device or cloud worker fails before any
// model call with "Session capability metadata requires worker preparation"
// (openclaw/openclaw#182647). The capability store only answers synchronous
// reads inside a prepared scope; the local turn wraps its preparation and
// inference in `withPreparedSessionCapabilityRead`, the worker turn does not.
// The scope loads whatever a read needs and retries, so wrapping the turn entry
// point restores the behaviour the local path already has.
//
// Anchored by symbol, never by file name or line number: dist chunk names change
// every release. When an anchor disappears the build fails and names this
// overlay, so an unpatched gateway can never ship silently.

import fs from "node:fs";
import path from "node:path";

const TAG = "openclaw worker capability-read patch";
const POLICY_MARKER = "async function withPreparedSessionCapabilityRead";
const TURN_SIGNATURE = "async function executeWorkerTurn(params) {";
const LOCAL_ALIAS = "__nixfilesPrepareCapabilityReads";
const TURN_SIGNATURE_ALIASED = `async function executeWorkerTurn(params) {\n\treturn ${LOCAL_ALIAS}(async () => {`;

function fail(message) {
  console.error(`${TAG}: ${message}`);
  process.exit(1);
}

function functionBodyEnd(source, signature) {
  const start = source.indexOf(signature);
  if (start === -1) return -1;
  const open = source.indexOf("{", start);
  if (open === -1) return -1;
  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") depth += 1;
    else if (char === "}") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
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

const [accessorName, accessorSource] = findUnique(POLICY_MARKER, "the prepared capability reader");
const TURN_MARKER = TURN_SIGNATURE;
const [turnName, turnSource] = findUnique(TURN_MARKER, "the worker turn entry point");

if (turnSource.includes(LOCAL_ALIAS)) {
  fail(
    "the package already carries this patch - upstream wrapped the worker turn. " +
      "Delete prepare-worker-capability-reads.mjs from packages/overlays/fix/openclaw.",
  );
}

const exportMatch = accessorSource.match(/export \{[^}]*withPreparedSessionCapabilityRead as (\w+)[^}]*\};/);
if (!exportMatch) fail(`${accessorName} no longer exports withPreparedSessionCapabilityRead`);

const end = functionBodyEnd(turnSource, TURN_SIGNATURE);
if (end === -1) fail(`${TURN_SIGNATURE} not found or its body is unbalanced in ${turnName}`);

const withWrapper = turnSource.replace(TURN_SIGNATURE, TURN_SIGNATURE_ALIASED);
const shiftedEnd = end + (TURN_SIGNATURE_ALIASED.length - TURN_SIGNATURE.length);
const patchedTurn = `${withWrapper.slice(0, shiftedEnd)}\t});\n${withWrapper.slice(shiftedEnd)}`;

const importLine = `import { ${exportMatch[1]} as ${LOCAL_ALIAS} } from "./${accessorName}";\n`;
const final = patchedTurn.replace(/^/, importLine);

if (!final.includes(importLine) || !final.includes(TURN_SIGNATURE_ALIASED)) {
  fail("the transform did not produce the expected module; refusing to write a partial patch");
}

fs.writeFileSync(path.join(distDir, turnName), final);
console.log(`${TAG}: ${turnName} now prepares capability reads for the whole turn`);
