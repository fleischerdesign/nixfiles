import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { test } from "node:test";

const executable = process.env.PI_AUTH_RECONCILER;
const pi = await import(pathToFileURL(path.join(process.env.PI_PACKAGE_ROOT, "dist/core/auth-storage.js")));
const oauth = { type: "oauth", access: "test-access", refresh: "test-refresh", expires: 9999999999999 };
const write = (file, value) => fs.writeFileSync(file, JSON.stringify(value));
const read = (file) => JSON.parse(fs.readFileSync(file, "utf8"));

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-auth-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, "secret ' source.json");
  const spec = path.join(root, "spec.json");
  const auth = path.join(root, "agent", "auth.json");
  const declare = (providers) => {
    write(source, Object.fromEntries(providers.map((p) => [p, { type: "api_key", key: `secret-${p}` }])));
    write(spec, { providers, source, jq: process.env.PI_AUTH_JQ });
  };
  declare(["provider-a"]);
  const run = (success = true) => {
    const result = spawnSync(executable, [spec, auth], { encoding: "utf8" });
    assert.equal(result.status === 0, success, result.stderr);
    return result;
  };
  const seed = (value) => {
    fs.mkdirSync(path.dirname(auth), { recursive: true });
    write(auth, value);
  };
  return { source, spec, auth, declare, run, seed };
}

test("declared keys resolve through Pi; file is private and repeated activation is idempotent", async (t) => {
  const f = fixture(t);
  // Exercise JSON and shell quoting, not just ordinary provider identifiers.
  const provider = "provider'\"$(false)";
  f.declare([provider]);
  f.run();
  assert.equal(fs.statSync(f.auth).mode & 0o777, 0o600);
  const credential = await pi.AuthStorage.create(f.auth).read(provider);
  assert.equal(credential.key, `secret-${provider}`);
  assert.ok(!fs.readFileSync(f.auth, "utf8").includes(`secret-${provider}`));
  const before = fs.statSync(f.auth);
  f.run();
  assert.equal(fs.statSync(f.auth).ino, before.ino);
  assert.equal(fs.statSync(f.auth).mtimeMs, before.mtimeMs);
});

test("updates and removal preserve OAuth and unmanaged API keys, including an empty inventory", (t) => {
  const f = fixture(t);
  const manual = { type: "api_key", key: "manual" };
  f.seed({ subscription: oauth, manual, ambient: { type: "api_key", env: { REGION: "test" } } });
  f.run();
  f.declare(["provider-b"]);
  f.run();
  assert.ok(!Object.hasOwn(read(f.auth), "provider-a"));
  assert.deepEqual(read(f.auth).subscription, oauth);
  f.declare([]);
  f.run();
  assert.deepEqual(read(f.auth), { subscription: oauth, manual, ambient: { type: "api_key", env: { REGION: "test" } } });
});

test("a declared API key wins its provider ID; removed declarations preserve later OAuth login", (t) => {
  const f = fixture(t);
  f.seed({ "provider-a": oauth });
  f.run();
  assert.equal(read(f.auth)["provider-a"].type, "api_key");
  f.seed({ "provider-a": oauth });
  f.declare([]);
  f.run();
  assert.deepEqual(read(f.auth), { "provider-a": oauth });
});

test("legacy symlink becomes a regular file without modifying its source", (t) => {
  const f = fixture(t);
  fs.mkdirSync(path.dirname(f.auth));
  const hmLink = path.join(path.dirname(f.source), "home-manager-link");
  fs.symlinkSync(f.source, hmLink);
  fs.symlinkSync(hmLink, f.auth);
  const original = fs.readFileSync(f.source, "utf8");
  fs.chmodSync(f.source, 0o400);
  f.run();
  assert.ok(fs.lstatSync(f.auth).isFile());
  assert.equal(fs.readFileSync(f.source, "utf8"), original);
  assert.equal(fs.statSync(f.source).mode & 0o777, 0o400);
});

test("malformed, empty, and unsupported auth files fail without changing their bytes", (t) => {
  const f = fixture(t);
  f.seed({});
  for (const content of ["{broken", "", "[]", "null", '{"p":{"type":"future"}}']) {
    fs.writeFileSync(f.auth, content);
    f.run(false);
    assert.equal(fs.readFileSync(f.auth, "utf8"), content);
    assert.ok(!fs.existsSync(f.auth + ".lock"));
  }
});

test("invalid source, missing keys, and unknown symlinks preserve the original", (t) => {
  const f = fixture(t);
  f.seed({ subscription: oauth });
  const original = fs.readFileSync(f.auth, "utf8");
  for (const data of [{}, { "provider-a": { type: "api_key", key: "" } }]) {
    write(f.source, data);
    f.run(false);
    assert.equal(fs.readFileSync(f.auth, "utf8"), original);
  }
  fs.unlinkSync(f.source);
  f.run(false);
  assert.equal(fs.readFileSync(f.auth, "utf8"), original);
  f.declare(["provider-a"]);
  const other = f.auth + ".other";
  fs.renameSync(f.auth, other);
  fs.symlinkSync(other, f.auth);
  f.run(false);
  assert.ok(fs.lstatSync(f.auth).isSymbolicLink());
  assert.equal(fs.readFileSync(other, "utf8"), original);
});

test("reconciliation waits for Pi's real lock and preserves its refreshed credential", async (t) => {
  const f = fixture(t);
  f.seed({ subscription: oauth });
  const backend = new pi.FileAuthStorageBackend(f.auth);
  let childResult;
  const refreshed = { ...oauth, access: "refreshed-access", refresh: "refreshed-refresh" };
  await backend.withLockAsync(async () => {
    const child = spawn(executable, [f.spec, f.auth], { stdio: ["ignore", "pipe", "pipe"] });
    childResult = new Promise((resolve, reject) => {
      let stderr = "";
      child.stderr.on("data", (data) => { stderr += data; });
      child.on("error", reject);
      child.on("close", (code) => {
        if (code !== 0) reject(new Error(stderr)); else resolve();
      });
    });
    await new Promise((resolve) => setTimeout(resolve, 350));
    assert.equal(child.exitCode, null, "reconciler must wait while Pi holds the lock");
    return { next: JSON.stringify({ subscription: refreshed }) };
  });
  await childResult;
  assert.deepEqual(read(f.auth).subscription, refreshed);
  assert.equal((await pi.AuthStorage.create(f.auth).read("provider-a")).key, "secret-provider-a");
});
