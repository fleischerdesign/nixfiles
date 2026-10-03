// Exercise the pinned Gateway's real auth decision function, not a reimplementation.
// Credential-verifier callbacks isolate auth routing; live enrollment verifies actual tokens.
import assert from "node:assert/strict";
import { readdir } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const dist = `${process.argv[2]}/lib/node_modules/openclaw/dist`;
const modules = (await readdir(dist)).filter(name => /^node-connect-reconcile-.*\.mjs$/.test(name));
assert.equal(modules.length, 1, "Expected exactly one upstream node auth module");
const { o: decide } = await import(pathToFileURL(`${dist}/${modules[0]}`));
assert.equal(typeof decide, "function", "Expected upstream resolveConnectAuthDecision export");

async function measure(reason, kind, valid) {
  let verified = 0;
  const verify = async () => { verified++; return { ok: valid }; };
  const result = await decide({
    state: {
      authResult: { ok: false, reason }, authOk: false, authMethod: "token",
      ...(kind === "bootstrap" ? { bootstrapTokenCandidate: "test-credential" }
        : { deviceTokenCandidate: "test-credential", deviceTokenCandidateSource: "explicit-device-token" }),
    },
    hasDeviceIdentity: true, deviceId: "test-device", publicKey: "test-public-key",
    role: "node", scopes: [],
    verifyBootstrapToken: verify, verifyDeviceToken: verify,
  });
  assert.equal(result.authOk, valid && reason !== "proxy_attribution_required");
  assert.equal(verified, reason === "proxy_attribution_required" ? 0 : 1);
  if (result.authOk) assert.equal(result.authMethod, `${kind}-token`);
}

for (const reason of ["trusted_proxy_untrusted_source", "trusted_proxy_user_missing", "proxy_attribution_required"]) {
  for (const kind of ["bootstrap", "device"]) {
    for (const valid of [false, true]) await measure(reason, kind, valid);
  }
}
console.log("Expected valid device/bootstrap credentials to bypass absent proxy identity, invalid credentials and unattributable proxy traffic rejected: verified");
