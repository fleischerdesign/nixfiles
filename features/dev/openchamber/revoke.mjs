#!/usr/bin/env node
// Server-side reconciliation of the Nix device allowlist against the running server's token store.
//
// Removing a device from Nix removes its SSH grant, so it cannot mint again. This helper closes the
// other half: an already-issued token is revoked when the device is no longer allowed. It only
// touches records the bootstrap created (`openchamber-bootstrap:<id>`); a manually paired phone is
// never in that namespace and is never affected.
import fs from 'node:fs';

const configPath = process.env.OPENCHAMBER_REVOKE_CONFIG || '/etc/openchamber/revoke.json';

let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (error) {
  process.stderr.write(`revoke: configuration unavailable: ${error?.message || error}\n`);
  process.exit(69);
}

const server = String(config.serverUrl || '').replace(/\/$/, '');
const passwordFile = config.passwordFile;
const allowlistFile = config.allowlistFile;
if (!server || !passwordFile || !allowlistFile) {
  process.stderr.write('revoke: configuration incomplete\n');
  process.exit(69);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const waitForHealth = async () => {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch(`${server}/health`, { signal: AbortSignal.timeout(2000) });
      if (response.ok) return true;
    } catch {
      // The server is still starting.
    }
    await sleep(1000);
  }
  return false;
};

// A missing server is not a revocation failure: the timer runs again. It is still visible in the
// unit log so a server that never comes up is not silently treated as reconciled.
if (!(await waitForHealth())) {
  process.stderr.write('revoke: server did not become healthy; retrying on the next timer\n');
  process.exit(0);
}

let allowlist;
try {
  allowlist = new Set(fs.readFileSync(allowlistFile, 'utf8').split(/\s+/).filter(Boolean));
} catch {
  process.stderr.write('revoke: allowlist unavailable\n');
  process.exit(69);
}

let password;
try {
  password = fs.readFileSync(passwordFile, 'utf8').replace(/\r?\n$/, '');
} catch {
  process.stderr.write('revoke: credential unavailable\n');
  process.exit(69);
}

let login;
try {
  login = await fetch(`${server}/auth/session`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ password }),
    signal: AbortSignal.timeout(10000),
  });
} catch {
  process.stderr.write('revoke: server unreachable\n');
  process.exit(0);
}
const cookie = (login.headers.get('set-cookie') || '').split(';')[0];
if (!login.ok || !cookie.startsWith('oc_ui_session')) {
  process.stderr.write(`revoke: login failed ${login.status}\n`);
  process.exit(1);
}

let listed;
try {
  listed = await fetch(`${server}/api/client-auth/clients`, {
    headers: { cookie, accept: 'application/json' },
    signal: AbortSignal.timeout(10000),
  });
} catch {
  process.stderr.write('revoke: client list unreachable\n');
  process.exit(0);
}
if (!listed.ok) {
  process.stderr.write(`revoke: client list failed ${listed.status}\n`);
  process.exit(1);
}

const body = await listed.json();
const clients = Array.isArray(body?.clients) ? body.clients : [];
// Reserved namespace: every label beginning with this prefix belongs to the declared device
// allowlist. A hand-created client must not use it; ids are bounded so the label is never
// truncated by upstream and the suffix is exactly the device id.
const prefix = 'openchamber-bootstrap:';

let revoked = 0;
for (const client of clients) {
  if (client?.revokedAt || client?.clientKind !== 'desktop') continue;
  const label = typeof client?.label === 'string' ? client.label : '';
  if (!label.startsWith(prefix)) continue;
  const deviceId = label.slice(prefix.length);
  if (allowlist.has(deviceId)) continue;

  const response = await fetch(`${server}/api/client-auth/clients/${encodeURIComponent(client.id)}`, {
    method: 'DELETE',
    headers: { cookie, accept: 'application/json' },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) {
    process.stderr.write(`revoke: failed to revoke ${deviceId}: ${response.status}\n`);
    process.exit(1);
  }
  revoked += 1;
  process.stderr.write(`revoke: revoked ${deviceId}\n`);
}

process.stderr.write(`revoke: reconciled, ${revoked} token(s) revoked\n`);
