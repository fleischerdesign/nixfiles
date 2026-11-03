#!/usr/bin/env node
// Client-side pre-app adapter.
//
// Reconciles the desired managed host from a token-free registry into OpenChamber's own
// settings.json. It mints a device token over the restricted SSH bootstrap only when the existing
// token is missing or the server says 401. Every unmanaged key and host in the settings root is
// preserved; the write is atomic and mode 0600.
//
// Exit codes: 0 written, 4 bootstrap denied (no token), 5 mint failed, 64 usage, 70 adapter error,
// 75 the app already owns the profile.
import fsp from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { spawn } from 'node:child_process';

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}
const registryPath = args.get('--registry');
const statePath = args.get('--state');
const settingsPath = args.get('--settings');
const appUserData = args.get('--app-user-data');
if (!registryPath || !statePath || !settingsPath || !appUserData) {
  process.stderr.write(
    'provision: --registry, --state, --settings and --app-user-data are required\n',
  );
  process.exit(64);
}

const log = (event, detail = {}) => process.stderr.write(`${JSON.stringify({ event, ...detail })}\n`);

// Electron's real ProcessSingleton artifacts live in userData. A stale symlink (dead pid) is not a
// running app; a live pid plus an accepting SingletonSocket is.
const appRunning = async () => {
  const lock = path.join(appUserData, 'SingletonLock');
  let target;
  try {
    target = await fsp.readlink(lock);
  } catch {
    return false;
  }
  const match = /^(.*)-(\d+)$/.exec(target);
  const pid = match ? Number(match[2]) : null;
  if (pid) {
    try {
      process.kill(pid, 0);
    } catch {
      return false;
    }
  }
  const socket = path.join(appUserData, 'SingletonSocket');
  return await new Promise((resolve) => {
    const connection = net.connect(socket);
    const done = (value) => {
      connection.destroy();
      resolve(value);
    };
    connection.setTimeout(500);
    connection.once('connect', () => done(true));
    connection.once('error', () => done(Boolean(pid)));
    connection.once('timeout', () => done(Boolean(pid)));
  });
};

const readJson = async (file) => {
  try {
    return JSON.parse(await fsp.readFile(file, 'utf8'));
  } catch (error) {
    if (error?.code === 'ENOENT') return {};
    throw error;
  }
};

const atomicWrite = async (file, value, mode = 0o600) => {
  const directory = path.dirname(file);
  await fsp.mkdir(directory, { recursive: true, mode: 0o700 });
  const temporary = path.join(directory, `.${path.basename(file)}.${process.pid}.${Date.now()}.tmp`);
  const handle = await fsp.open(temporary, 'w', mode);
  try {
    await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`);
    await handle.sync();
  } finally {
    await handle.close();
  }
  await fsp.rename(temporary, file);
  try {
    const directoryHandle = await fsp.open(directory, 'r');
    await directoryHandle.sync().catch(() => {});
    await directoryHandle.close();
  } catch {
    // Directory fsync is best-effort on filesystems that do not support it.
  }
};

const normalizeUrl = (raw) => {
  try {
    const parsed = new URL(String(raw).trim());
    if (!['http:', 'https:'].includes(parsed.protocol)) return null;
    parsed.hash = '';
    return parsed.toString();
  } catch {
    return null;
  }
};

// Upstream's own persisted shape. Unknown host fields would be dropped by buildStoredHostEntry, so
// this writes only the fields upstream stores.
const storedEntry = ({ id, label, url, apiUrl, clientToken }) => {
  const entry = { id, label: label || url, url };
  const api = normalizeUrl(apiUrl || url);
  if (api) entry.apiUrl = api;
  if (clientToken) entry.clientToken = clientToken;
  return entry;
};

const probe = async (base, token) => {
  try {
    const response = await fetch(`${base.replace(/\/$/, '')}/auth/session`, {
      headers: { accept: 'application/json', authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(4000),
    });
    if (response.status === 200) return 'valid';
    if (response.status === 401) return 'invalid';
    return `http-${response.status}`;
  } catch {
    return 'unreachable';
  }
};

// The mint command is the Nix-declared restricted SSH invocation. Its stdout is a pipe, never argv;
// only the token is accepted, and it is never printed.
const mint = (command) =>
  new Promise((resolve) => {
    const child = spawn('/bin/sh', ['-c', command], { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    child.stdout.on('data', (chunk) => {
      if (out.length < 4096) out += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      if (err.length < 4096) err += chunk.toString();
    });
    child.once('error', () => resolve({ ok: false, code: 'spawn' }));
    child.once('exit', (code) => {
      const token = out.trim();
      if (code === 0 && /^oc_client_[A-Za-z0-9_-]{40,}$/.test(token)) {
        resolve({ ok: true, token });
        return;
      }
      resolve({ ok: false, code: `exit-${code}`, detail: err.trim().slice(0, 200) });
    });
  });

try {
  if (await appRunning()) {
    log('app-running-defer', { appUserData });
    process.exit(75);
  }

  const registry = await readJson(registryPath);
  const desired = Array.isArray(registry.hosts) ? registry.hosts : null;
  if (!desired) {
    log('registry-invalid', { registryPath });
    process.exit(70);
  }

  const state = await readJson(statePath);
  const previous = Array.isArray(state.previousManaged) ? state.previousManaged : [];
  const settings = await readJson(settingsPath);

  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
    log('settings-invalid', { settingsPath });
    process.exit(70);
  }
  if ('desktopHosts' in settings && !Array.isArray(settings.desktopHosts)) {
    // A future settings schema is not silently overwritten by an adapter written for this one.
    log('settings-schema-unknown', { settingsPath });
    process.exit(70);
  }

  const hosts = Array.isArray(settings.desktopHosts) ? settings.desktopHosts.slice() : [];
  const desiredIds = new Set(desired.map((host) => host.id));
  const removeIds = new Set(previous.filter((id) => !desiredIds.has(id)));
  const nextHosts = hosts.filter((host) => host && !removeIds.has(host.id));

  for (const host of desired) {
    const id = host.id;
    const url = normalizeUrl(host.url);
    if (!id || !url) {
      log('skip-invalid-host', { id });
      continue;
    }
    const index = nextHosts.findIndex((entry) => entry.id === id);
    const existing = index >= 0 ? nextHosts[index] : null;
    let token = existing?.clientToken || '';

    let needMint = !token;
    if (token) {
      const status = await probe(url, token);
      log('probe', { id, state: status });
      if (status === 'invalid') needMint = true;
      else if (status === 'unreachable') {
        log('network-error-keep-token', { id });
      } else if (status !== 'valid') {
        log('probe-unexpected-keep-token', { id, state: status });
      }
    }

    if (needMint) {
      if (!host.mintCommand) {
        log('missing-mint-command', { id });
        process.exitCode = 3;
        continue;
      }
      const result = await mint(host.mintCommand);
      if (result.ok) {
        token = result.token;
        log('token-minted', { id });
      } else {
        const denied = result.code === 'exit-77';
        log(denied ? 'bootstrap-denied-do-not-enroll' : 'mint-failed', {
          id,
          code: result.code,
          detail: result.detail,
        });
        if (denied) {
          if (existing) delete existing.clientToken;
          process.exitCode = 4;
        } else {
          process.exitCode = process.exitCode || 5;
        }
        continue;
      }
    }

    const entry = storedEntry({
      id,
      label: host.label || id,
      url: host.url,
      apiUrl: host.apiUrl,
      clientToken: token,
    });
    if (index >= 0) nextHosts[index] = { ...nextHosts[index], ...entry };
    else nextHosts.push(entry);
  }

  settings.desktopHosts = nextHosts;
  const defaultId = desired.length === 1 ? desired[0].id : registry.defaultHostId;
  if (defaultId) settings.desktopDefaultHostId = defaultId;
  if (desired.length > 0) settings.desktopInitialHostChoiceCompleted = true;

  await atomicWrite(settingsPath, settings);
  await atomicWrite(statePath, { ...state, previousManaged: [...desiredIds] });
  log('settings-written', {
    hosts: nextHosts.length,
    defaultHostId: settings.desktopDefaultHostId,
  });
  process.exit(process.exitCode || 0);
} catch (error) {
  log('adapter-error', { message: String(error?.message || error) });
  process.exit(70);
}
