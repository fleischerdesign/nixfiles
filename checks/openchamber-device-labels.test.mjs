// Device identity at the boundary where it is decided: the real client-auth runtime, the real mint
// and revoke helpers, and a fake HTTP shell around that runtime. A managed device is identified by
// the label prefix; upstream truncates labels at 80 characters, so a device id that does not fit
// would be stored under a different id and revoked as unmanaged. This also proves the revocation
// and re-enrollment semantics without touching a real device.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [mintScript, revokeScript, runtimeModule] = process.argv.slice(2);
if (!mintScript || !revokeScript || !runtimeModule) {
  throw new Error('usage: openchamber-device-labels.test.mjs <mint> <revoke> <remote-clients.js>');
}

const { createRemoteClientAuthRuntime } = await import(pathToFileURL(runtimeModule).href);
const PREFIX = 'openchamber-bootstrap:';
const MAX_LABEL_LENGTH = 80;
const MAX_ID = MAX_LABEL_LENGTH - PREFIX.length;
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'openchamber-labels-'));
const storePath = path.join(root, 'remote-clients.json');
const passwordFile = path.join(root, 'password');
const allowlistFile = path.join(root, 'bootstrap-devices');
const password = `fixture-${crypto.randomBytes(6).toString('hex')}`;
fs.writeFileSync(passwordFile, `${password}\n`, { mode: 0o600 });

const runtime = createRemoteClientAuthRuntime({
  fsPromises: fs.promises,
  path,
  crypto,
  storePath,
});

const json = (res, status, value) => {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(value));
};
const server = http.createServer(async (req, res) => {
  let body = '';
  for await (const chunk of req) body += chunk;
  const url = new URL(req.url, 'http://fixture');
  if (url.pathname === '/health') return json(res, 200, { ok: true });
  if (url.pathname === '/auth/session' && req.method === 'POST') {
    if (JSON.parse(body || '{}').password !== password) return json(res, 401, {});
    res.writeHead(200, { 'set-cookie': 'oc_ui_session=fixture; Path=/; HttpOnly' });
    return res.end('{}');
  }
  if (!(req.headers.cookie || '').startsWith('oc_ui_session=')) return json(res, 401, {});
  if (url.pathname === '/api/client-auth/clients' && req.method === 'GET') {
    return json(res, 200, { clients: await runtime.listClients() });
  }
  if (url.pathname === '/api/client-auth/clients' && req.method === 'POST') {
    const created = await runtime.createClient(JSON.parse(body));
    return json(res, 200, { token: created.token, client: created.client });
  }
  const match = url.pathname.match(/^\/api\/client-auth\/clients\/([^/]+)$/);
  if (match && req.method === 'DELETE') {
    const result = await runtime.revokeClient(decodeURIComponent(match[1]));
    return json(res, result.revoked ? 200 : 404, result);
  }
  return json(res, 404, {});
});

await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const serverUrl = `http://127.0.0.1:${server.address().port}`;

const writeConfig = (file, name) => {
  fs.writeFileSync(file, JSON.stringify({ serverUrl, passwordFile, allowlistFile }), { mode: 0o600 });
  return file;
};
// The fake server runs in this process, so the child must be asynchronous: spawnSync would block
// the event loop and the child's HTTP requests could never be answered.
const run = (script, configFile, envName, args = []) =>
  new Promise((resolve) => {
    const child = spawn(process.execPath, [script, ...args], {
      env: { ...process.env, [envName]: configFile },
    });
    let out = '';
    let err = '';
    child.stdout.on('data', (chunk) => { out += chunk.toString(); });
    child.stderr.on('data', (chunk) => { err += chunk.toString(); });
    child.once('error', () => resolve({ code: null, out, err }));
    child.once('close', (code) => resolve({ code, out, err }));
  });
const runMint = (id) =>
  run(mintScript, writeConfig(path.join(root, 'mint.json'), 'mint'), 'OPENCHAMBER_MINT_CONFIG', [id]);
const runRevoke = () =>
  run(revokeScript, writeConfig(path.join(root, 'revoke.json'), 'revoke'), 'OPENCHAMBER_REVOKE_CONFIG');
const clients = async () => runtime.listClients();

const failures = [];
const check = (name, ok, detail = '') => {
  if (!ok) failures.push(`${name}${detail ? `: ${detail}` : ''}`);
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : ` -- ${detail}`}`);
};

try {
  // A manual client outside the managed namespace must never be touched.
  const manual = await runtime.createClient({ label: 'Phone', clientKind: 'phone', dedupeKey: 'phone' });

  // The longest id the declared namespace can carry must round-trip untruncated.
  const allowedId = 'a'.repeat(MAX_ID);
  fs.writeFileSync(allowlistFile, `${allowedId}\n`);
  const allowed = await runMint(allowedId);
  check('longest managed id mints', allowed.code === 0 && /^oc_client_/.test(allowed.out), allowed.err.trim());
  const allowedClient = (await clients()).find((entry) => entry.label === `${PREFIX}${allowedId}`);
  check('longest managed label round-trips', Boolean(allowedClient) && allowedClient.label.length === MAX_LABEL_LENGTH);
  check(
    'minted token authenticates',
    Boolean(await runtime.authenticateBearerToken(allowed.out.trim())),
  );

  // One character more would be truncated by upstream, so the helper must refuse before writing.
  const oversizedId = 'b'.repeat(MAX_ID + 1);
  fs.writeFileSync(allowlistFile, `${allowedId}\n${oversizedId}\n`);
  const oversized = await runMint(oversizedId);
  check('oversized id is refused', oversized.code === 64, `${oversized.code} ${oversized.err.trim()}`);
  check(
    'oversized id created no record',
    !(await clients()).some((entry) => entry.label.startsWith(`${PREFIX}${oversizedId}`)),
  );

  // Upstream really truncates: prove the boundary this guard exists for.
  const truncated = await runtime.createClient({
    label: `${PREFIX}${oversizedId}`,
    clientKind: 'desktop',
    dedupeKey: 'fixture:truncated',
  });
  check(
    'upstream label ceiling truncates',
    truncated.client.label.length === MAX_LABEL_LENGTH && truncated.client.label !== `${PREFIX}${oversizedId}`,
    truncated.client.label,
  );
  await runtime.revokeClient(truncated.client.id);

  // A device removed from the declaration loses its managed token; manual clients survive.
  const removedId = 'retired-device';
  const removed = await runtime.createClient({
    label: `${PREFIX}${removedId}`,
    clientKind: 'desktop',
    dedupeKey: `device:${removedId}`,
  });
  const revoked = await runRevoke();
  check('revoke exits successfully', revoked.code === 0, revoked.err.trim());
  const afterRevoke = await clients();
  check(
    'removed managed device is revoked',
    Boolean(afterRevoke.find((entry) => entry.id === removed.client.id)?.revokedAt),
  );
  check(
    'allowed managed device is not revoked',
    !afterRevoke.find((entry) => entry.id === allowedClient.id)?.revokedAt,
  );
  check(
    'manual client is not revoked',
    !afterRevoke.find((entry) => entry.id === manual.client.id)?.revokedAt,
  );

  // Re-enrollment: upstream replaces the dedupe-keyed record, so the new token is valid and not
  // a resurrected revoked one.
  fs.writeFileSync(allowlistFile, `${allowedId}\n${removedId}\n`);
  const reenrolled = await runMint(removedId);
  check('re-enrolled device mints', reenrolled.code === 0, reenrolled.err.trim());
  const afterReenroll = (await clients()).filter((entry) => entry.label === `${PREFIX}${removedId}`);
  check('re-enrollment leaves one record', afterReenroll.length === 1, JSON.stringify(afterReenroll));
  check('re-enrolled record is not revoked', !afterReenroll[0]?.revokedAt);
  check(
    're-enrolled token authenticates',
    Boolean(await runtime.authenticateBearerToken(reenrolled.out.trim())),
  );
} finally {
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(root, { recursive: true, force: true });
}

if (failures.length > 0) {
  console.error(`\n${failures.length} failure(s)`);
  process.exit(1);
}
console.log('\nall device label checks passed');
