// Acceptance for the server-side device bootstrap: real HTTP, the real server binary, the real mint
// and revoke helpers. No mock stands in for the auth or client-management routes.
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const [bin, mintBin, revokeBin] = process.argv.slice(2);
if (!bin || !mintBin || !revokeBin) {
  throw new Error('usage: openchamber-api.test.mjs <server> <mint> <revoke>');
}

const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'oc-api-'));
const dataDir = path.join(root, 'data');
const allowlist = path.join(root, 'bootstrap-devices');
const passwordFile = path.join(root, 'password');
const mintConfig = path.join(root, 'mint.json');
const revokeConfig = path.join(root, 'revoke.json');
const password = `dummy-${crypto.randomBytes(8).toString('hex')}`;
const port = 39000 + Math.floor(Math.random() * 1000);
const base = `http://127.0.0.1:${port}`;

await fsp.mkdir(dataDir, { recursive: true });
await fsp.writeFile(passwordFile, `${password}\n`, { mode: 0o600 });
await fsp.writeFile(allowlist, 'hom-wrk-01\n', { mode: 0o644 });
for (const file of [mintConfig, revokeConfig]) {
  await fsp.writeFile(
    file,
    JSON.stringify({
      serverUrl: base,
      passwordFile,
      allowlistFile: allowlist,
    }),
    { mode: 0o600 },
  );
}

const results = [];
const record = (name, ok, detail = {}) => {
  results.push({ name, ok });
  console.log(JSON.stringify({ probe: name, ok, ...detail }));
};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let server;
const start = async () => {
  server = spawn(
    bin,
    ['serve', '--host', '127.0.0.1', '--port', String(port), '--foreground', '--ui-password', password],
    {
      env: {
        ...process.env,
        HOME: root,
        OPENCHAMBER_DATA_DIR: dataDir,
        OPENCHAMBER_RUNTIME: 'desktop',
        NODE_ENV: 'production',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  server.stdout.on('data', () => {});
  server.stderr.on('data', () => {});
  for (let attempt = 0; attempt < 120; attempt += 1) {
    try {
      const response = await fetch(`${base}/health`, { signal: AbortSignal.timeout(1000) });
      if (response.ok) return;
    } catch {
      // still starting
    }
    await sleep(250);
  }
  throw new Error('server did not become healthy');
};
const stop = async () => {
  if (!server || server.exitCode !== null) return;
  server.kill('SIGTERM');
  await Promise.race([new Promise((resolve) => server.once('exit', resolve)), sleep(5000)]);
  if (server.exitCode === null) server.kill('SIGKILL');
};

const run = (command, args, env = {}) =>
  new Promise((resolve) => {
    const child = spawn(command, args, {
      env: { ...process.env, OPENCHAMBER_MINT_CONFIG: mintConfig, OPENCHAMBER_REVOKE_CONFIG: revokeConfig, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let out = '';
    let err = '';
    child.stdout.on('data', (chunk) => {
      out += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      err += chunk.toString();
    });
    child.once('exit', (code) => resolve({ code, out: out.trim(), err: err.trim() }));
  });

const login = async () => {
  const response = await fetch(`${base}/auth/session`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ password }),
  });
  if (!response.ok) throw new Error(`login failed ${response.status}`);
  return (response.headers.get('set-cookie') || '').split(';')[0];
};

const bearer = (token) =>
  fetch(`${base}/auth/session`, {
    headers: { accept: 'application/json', authorization: `Bearer ${token}` },
  });

try {
  await start();

  const mint1 = await run(mintBin, ['hom-wrk-01']);
  record('mint-issues-token', mint1.code === 0 && /^oc_client_/.test(mint1.out), { code: mint1.code });

  const check1 = await bearer(mint1.out);
  record('bearer-valid', check1.status === 200, { status: check1.status });

  const cookie = await login();
  const list = await fetch(`${base}/api/client-auth/clients`, {
    headers: { cookie, accept: 'application/json' },
  });
  const clients = (await list.json()).clients || [];
  const managed = clients.filter((client) => client.label === 'openchamber-bootstrap:hom-wrk-01');
  record(
    'one-managed-record',
    managed.length === 1 && managed[0].clientKind === 'desktop' && managed[0].revokedAt === null,
    { count: managed.length, kind: managed[0]?.clientKind },
  );

  const mint2 = await run(mintBin, ['hom-wrk-01']);
  const oldCheck = await bearer(mint1.out);
  const newCheck = await bearer(mint2.out);
  record(
    'remint-replaces-token',
    mint2.code === 0 && oldCheck.status === 401 && newCheck.status === 200,
    { oldStatus: oldCheck.status, newStatus: newCheck.status },
  );

  await fsp.writeFile(allowlist, '', { mode: 0o644 });
  const revoked = await run(revokeBin, []);
  const revokedCheck = await bearer(mint2.out);
  record('revoke-invalidates', revoked.code === 0 && revokedCheck.status === 401, {
    code: revoked.code,
    status: revokedCheck.status,
  });

  const denied = await run(mintBin, ['hom-wrk-01']);
  record('removed-device-cannot-mint', denied.code === 77, { code: denied.code });

  await fsp.writeFile(allowlist, 'hom-wrk-01\n', { mode: 0o644 });
  const mint3 = await run(mintBin, ['hom-wrk-01']);
  const readded = await bearer(mint3.out);
  record('grant-reattaches-device', mint3.code === 0 && readded.status === 200, {
    code: mint3.code,
    status: readded.status,
  });

  const rejected = await run(mintBin, ['mob-nb-01']);
  record('unknown-device-not-allowed', rejected.code === 77, { code: rejected.code });
} finally {
  await stop();
  await fsp.rm(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }).catch(() => {});
}

const failed = results.filter((result) => !result.ok);
console.log(JSON.stringify({ summary: { total: results.length, failed: failed.length } }));
process.exit(failed.length === 0 ? 0 : 1);
