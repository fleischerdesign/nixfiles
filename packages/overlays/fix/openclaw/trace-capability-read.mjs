#!/usr/bin/env node
// TEMPORARY diagnostic patch: log the caller stack when the session capability
// guard rejects a synchronous read.
//
// The guard's exception reaches the journal without a stack, which is why the
// caller of "Session capability metadata requires worker preparation"
// (openclaw/openclaw#182647) is still unidentified. This prints one stack trace
// per rejection and changes no behaviour: the same error is thrown afterwards.
//
// Remove this file and its installPhase line once the caller is known.

import fs from "node:fs";
import path from "node:path";

const TAG = "openclaw capability-read trace";
const MARKER = "throw new SessionCapabilityReadRequired(query);";
// Also print what the scope prepared: a miss is either a missing scope or a key
// mismatch, and the two need different fixes.
const TRACED = `console.error("${TAG}: caller stack", JSON.stringify({ requested: readKey(query), scope: preparedScope ? [...preparedScope.entries.keys()] : null, retain: preparedScope?.retain ?? null }), new Error().stack);\n\t\t${MARKER}`;

function fail(message) {
  console.error(`${TAG}: ${message}`);
  process.exit(1);
}

const root = process.argv[2] ?? process.env.OPENCLAW_PACKAGE_ROOT;
if (!root) fail("pass the installed package root as the first argument");
const distDir = path.join(root, "dist");
if (!fs.existsSync(distDir)) fail(`dist directory missing under ${root}`);

const hits = fs
  .readdirSync(distDir, { withFileTypes: true })
  .filter((entry) => entry.isFile() && /\.m?js$/.test(entry.name))
  .map((entry) => entry.name)
  .filter((name) => fs.readFileSync(path.join(distDir, name), "utf8").includes(MARKER));

if (hits.length !== 1) fail(`expected exactly one module containing the guard throw, found ${hits.length}`);

const file = path.join(distDir, hits[0]);
const source = fs.readFileSync(file, "utf8");
if (source.includes(TAG)) fail("the package already carries this trace");

const patched = source.replace(MARKER, TRACED);
if (!patched.includes(TRACED)) fail("the transform did not produce the expected module");

fs.writeFileSync(file, patched);
console.log(`${TAG}: ${hits[0]} now reports the caller stack`);
