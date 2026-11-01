// Regression proof for the skill hardlink policy.
//
// The built package must read bundled, custodian and plugin skill trees whose files
// are hardlinked by the optimised Nix store, while a mutable root with a hardlinked
// file still fails. The policy unit cases cover the ownership and path negatives that
// cannot be created without a privileged user.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [gateway] = process.argv.slice(2);
if (!gateway) {
  console.error("usage: openclaw-skill-hardlink-policy.mjs <gateway-store-path>");
  process.exit(2);
}
process.env.OPENCLAW_NIX_MODE = "1";

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}
function pass(message) {
  console.log(`PASS: ${message}`);
}
function makeWritable(directory) {
  fs.chmodSync(directory, 0o700);
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) makeWritable(absolute);
    else if (entry.isFile()) fs.chmodSync(absolute, 0o600);
  }
}

function hardlinkedFile(root) {
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(absolute);
      else if (entry.isFile() && fs.statSync(absolute).nlink > 1) return absolute;
    }
  }
  return null;
}

const dist = path.join(gateway, "lib/node_modules/openclaw/dist");
if (!fs.existsSync(dist)) fail(`dist missing: ${dist}`);
const bundles = fs
  .readdirSync(dist, { withFileTypes: true })
  .filter((entry) => (entry.isFile() || entry.isSymbolicLink()) && /\.m?js$/.test(entry.name))
  .filter((entry) => {
    const source = fs.readFileSync(path.join(dist, entry.name), "utf8");
    return source.includes("Skill tree file could not be read") && source.includes("function readSkillBundleTree(");
  });
if (bundles.length !== 1) fail(`expected one skill bundle chunk, found ${bundles.length}`);

const bundle = await import(pathToFileURL(path.join(dist, bundles[0].name)));
const readSkillBundleTree = Object.values(bundle).find(
  (value) => typeof value === "function" && value.name === "readSkillBundleTree",
);
if (!readSkillBundleTree) fail("readSkillBundleTree is not exported by the built bundle");

const storeRoots = [
  ["custodian", path.join(gateway, "lib/node_modules/openclaw/custodian-skills/add-model-provider")],
  ["bundled", path.join(gateway, "lib/node_modules/openclaw/skills/spike")],
];
let pluginRoot = null;
const extensions = path.join(gateway, "lib/node_modules/openclaw/dist/extensions");
if (fs.existsSync(extensions)) {
  for (const extension of fs.readdirSync(extensions, { withFileTypes: true })) {
    if (!extension.isDirectory()) continue;
    const skills = path.join(extensions, extension.name, "skills");
    if (!fs.existsSync(skills)) continue;
    const candidate = fs
      .readdirSync(skills, { withFileTypes: true })
      .find((entry) => entry.isDirectory() && fs.existsSync(path.join(skills, entry.name, "SKILL.md")));
    if (candidate) {
      pluginRoot = path.join(skills, candidate.name);
      break;
    }
  }
}
if (!pluginRoot) fail("no plugin extension skill tree found in the gateway package");
storeRoots.push(["plugin", pluginRoot]);

for (const [label, root] of storeRoots) {
  const linked = hardlinkedFile(root);
  if (!linked) fail(`${label} skill tree is not hardlinked; the policy path is not exercised (${root})`);
  let files;
  try {
    files = await readSkillBundleTree(root);
  } catch (error) {
    fail(`${label} store skill tree was rejected: ${error?.message ?? error}`);
  }
  if (!Array.isArray(files) || files.length === 0) fail(`${label} store skill tree read returned no files`);
  pass(`${label} store skill tree reads through a hardlink (${path.relative(gateway, root)})`);
}

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-skill-hardlinks-"));
const storeSkill = path.join(gateway, "lib/node_modules/openclaw/skills/spike");

const mutableHardlinked = path.join(scratch, "mutable-hardlinked");
fs.cpSync(storeSkill, mutableHardlinked, { recursive: true });
const mutableLinked = hardlinkedFile(mutableHardlinked) ?? path.join(mutableHardlinked, "SKILL.md");
fs.linkSync(mutableLinked, path.join(scratch, "outside-link"));
try {
  await readSkillBundleTree(mutableHardlinked);
  fail("mutable skill tree with a hardlinked file was accepted");
} catch (error) {
  if (error?.code !== "INVALID_BUNDLE" || !/hardlinked path not allowed/i.test(error.message)) {
    fail(`mutable hardlinked tree failed for the wrong reason: ${error?.message ?? error}`);
  }
  pass("mutable skill tree with a hardlinked file is still rejected");
}

const mutableRegular = path.join(scratch, "mutable-regular");
fs.cpSync(storeSkill, mutableRegular, { recursive: true });
if (hardlinkedFile(mutableRegular)) fail("regular mutable copy unexpectedly contains a hardlink");
const regularFiles = await readSkillBundleTree(mutableRegular);
if (!regularFiles.length) fail("regular mutable skill tree read returned no files");
pass("mutable skill tree without hardlinks still reads");

const policyUrl = pathToFileURL(path.join(dist, "nix-skill-hardlink-policy.mjs"));
const { resourceHardlinkPolicy } = await import(policyUrl);
const nixMode = { OPENCLAW_NIX_MODE: "1" };

if (resourceHardlinkPolicy(storeSkill, { env: { OPENCLAW_NIX_MODE: "0" } }) !== "reject") {
  fail("policy accepted a store tree with Nix mode disabled");
}
pass("policy rejects a store tree when Nix mode is off");

if (resourceHardlinkPolicy(mutableRegular, { env: nixMode }) !== "reject") {
  fail("policy accepted a mutable path");
}
pass("policy rejects a mutable path");

const fakeStore = path.join(scratch, "fake-store");
const fakeOutput = path.join(fakeStore, "0123456789abcdef0123456789abcdef-pkg");
const fakeSkill = path.join(fakeOutput, "skill");
fs.mkdirSync(fakeSkill, { recursive: true });
fs.chmodSync(fakeStore, 0o755);
fs.chmodSync(fakeOutput, 0o555);
fs.chmodSync(fakeSkill, 0o555);
const fakeOptions = { env: nixMode, storeRoot: fakeStore };
if (resourceHardlinkPolicy(fakeSkill, fakeOptions) !== "allow") {
  fail("policy rejected a fake immutable store output");
}
pass("policy accepts an immutable output under the configured store root");

fs.chmodSync(fakeSkill, 0o755);
if (resourceHardlinkPolicy(fakeSkill, fakeOptions) !== "reject") {
  fail("policy accepted a writable store output");
}
fs.chmodSync(fakeSkill, 0o555);
pass("policy rejects a writable store output");

fs.chmodSync(fakeStore, 0o777);
if (resourceHardlinkPolicy(fakeSkill, fakeOptions) !== "reject") {
  fail("policy accepted a world-writable store root");
}
fs.chmodSync(fakeStore, 0o755);
pass("policy rejects a world-writable store root");

const storeStat = { isDirectory: () => true, mode: 0o040755, uid: 1000 };
const foreignStat = { isDirectory: () => true, mode: 0o040555, uid: 1001 };
const statSync = (candidate) => (candidate === fakeStore ? storeStat : foreignStat);
const realpathSync = (candidate) => candidate;
if (resourceHardlinkPolicy(fakeSkill, { ...fakeOptions, statSync, realpathSync }) !== "reject") {
  fail("policy accepted a store output owned by another account");
}
pass("policy rejects a store output owned by another account");

if (resourceHardlinkPolicy("/tmp/../tmp/not-a-store", { env: nixMode, realpathSync: () => "/tmp/not-a-store" }) !== "reject") {
  fail("policy accepted a non-store path");
}
pass("policy rejects a non-store path");

makeWritable(scratch);
fs.rmSync(scratch, { recursive: true, force: true });
console.log("skill hardlink policy: all checks passed");
process.exit(0);
