#!/usr/bin/env node
// Server-side SSH forced-command helper.
//
// Invoked only from an authorized_keys line with a constant device id:
//   restrict,command="/run/current-system/sw/bin/openchamber-mint hom-wrk-01" ssh-ed25519 AAAA...
//
// The device id is not taken from the client. The helper signs in with the server-only UI password,
// uses the resulting session cookie to create a non-expiring device token through the native
// client-management route, and writes only the token to stdout. The password never appears in argv
// or logs.
import fs from 'node:fs';

const deviceId = process.argv[2];
if (!/^[a-z0-9][a-z0-9-]{1,62}$/.test(deviceId || '')) {
  process.stderr.write('mint: invalid device id\n');
  process.exit(64);
}

const configPath = process.env.OPENCHAMBER_MINT_CONFIG || '/etc/openchamber/mint.json';

let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch {
  process.stderr.write('mint: configuration unavailable\n');
  process.exit(69);
}

const server = String(config.serverUrl || '').replace(/\/$/, '');
const passwordFile = config.passwordFile;
const allowlistFile = config.allowlistFile;
if (!server || !passwordFile || !allowlistFile) {
  process.stderr.write('mint: configuration incomplete\n');
  process.exit(69);
}

let allowlist;
try {
  allowlist = fs.readFileSync(allowlistFile, 'utf8').split(/\s+/).filter(Boolean);
} catch {
  process.stderr.write('mint: allowlist unavailable\n');
  process.exit(69);
}
if (!allowlist.includes(deviceId)) {
  process.stderr.write('mint: device not allowed\n');
  process.exit(77);
}

let password;
try {
  password = fs.readFileSync(passwordFile, 'utf8').replace(/\r?\n$/, '');
} catch {
  process.stderr.write('mint: credential unavailable\n');
  process.exit(69);
}
if (!password) {
  process.stderr.write('mint: credential empty\n');
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
  process.stderr.write('mint: server unreachable\n');
  process.exit(75);
}
if (login.status === 401) {
  process.stderr.write('mint: credential rejected\n');
  process.exit(77);
}
const cookie = (login.headers.get('set-cookie') || '').split(';')[0];
if (!login.ok || !cookie.startsWith('oc_ui_session')) {
  process.stderr.write(`mint: login failed ${login.status}\n`);
  process.exit(74);
}

// This route creates a persistent record. The login route's `issueClientToken` attaches the UI
// session's expiry, which would silently invalidate a device after the session TTL.
let created;
try {
  created = await fetch(`${server}/api/client-auth/clients`, {
    method: 'POST',
    headers: {
      cookie,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      label: `openchamber-bootstrap:${deviceId}`,
      clientKind: 'desktop',
      dedupeKey: `device:${deviceId}`,
    }),
    signal: AbortSignal.timeout(10000),
  });
} catch {
  process.stderr.write('mint: server unreachable\n');
  process.exit(75);
}
if (!created.ok) {
  process.stderr.write(`mint: server error ${created.status}\n`);
  process.exit(74);
}

let body;
try {
  body = await created.json();
} catch {
  process.stderr.write('mint: malformed response\n');
  process.exit(74);
}
const token = body?.token;
if (typeof token !== 'string' || !token.startsWith('oc_client_') || token.length < 40) {
  process.stderr.write('mint: no client token issued\n');
  process.exit(74);
}
process.stdout.write(token);
