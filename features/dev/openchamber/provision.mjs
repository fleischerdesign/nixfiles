#!/usr/bin/env node
// Client-side pre-app adapter.
//
// Reconciles the desired managed host from a token-free registry into OpenChamber's own
// settings.json. It mints a device token over the restricted SSH bootstrap only when the existing
// token is missing or the server says 401. Every unmanaged key and host in the settings root is
// preserved; the write is atomic and mode 0600.
//
// Exit codes: 0 written, 3 mint command missing, 4 bootstrap denied (no token), 5 mint failed,
// 6 local network access disabled because the native Local token could not be prepared (the app
// still starts on loopback), 64 usage, 70 adapter error, 75 the app already owns the profile.
import fsp from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
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

// Every external operation has a hard bound: an unreachable peer may delay a start, never hang it.
const PROBE_TIMEOUT_MS = 4_000;
const MINT_TIMEOUT_MS = 30_000;
const LOCAL_AUTH_ATTEMPTS = 3;
const LOCAL_AUTH_RETRY_MS = 250;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const withRetry = async (operation, attempts, delayMs) => {
  let last;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      last = error;
      if (attempt + 1 < attempts) await sleep(delayMs);
    }
  }
  throw last;
};

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
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
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
    let settled = false;
    const finish = (value) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    };
    const child = spawn('/bin/sh', ['-c', command], {
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: MINT_TIMEOUT_MS,
      killSignal: 'SIGKILL',
    });
    let out = '';
    let err = '';
    child.stdout.on('data', (chunk) => {
      if (out.length < 4096) out += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      if (err.length < 4096) err += chunk.toString();
    });
    child.once('error', () => finish({ ok: false, code: 'spawn' }));
    child.once('exit', (code, signal) => {
      const token = out.trim();
      if (code === 0 && /^oc_client_[A-Za-z0-9_-]{40,}$/.test(token)) {
        finish({ ok: true, token });
        return;
      }
      finish({
        ok: false,
        code: signal ? `signal-${signal}` : `exit-${code}`,
        detail: err.trim().slice(0, 200),
      });
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

  // Non-fatal outcomes are collected and only decide the exit code after every host is tried.
  const codes = new Set();

  // The desktop is a background application: its window close path hides to the tray while the
  // embedded engine keeps running (upstream reads this key before the window is created). Without
  // it, closing the window quits the process and its engine.
  settings.desktopMinimizeToTrayEnabled = true;

  // The native listener is configured through the same settings root upstream reads at spawn.
  // `desktopLanAccessEnabled` makes it bind 0.0.0.0, which upstream refuses without a password.
  // The password is read from a declared secret file, never taken from argv or the environment.
  const localNetwork = registry.localNetwork;
  if (localNetwork && typeof localNetwork === 'object') {
    const port = Number(localNetwork.port);
    let uiPassword = '';
    try {
      uiPassword = (await fsp.readFile(localNetwork.uiPasswordFile, 'utf8')).trim();
    } catch (error) {
      log('ui-password-unavailable', { code: error?.code || null });
      process.exit(70);
    }
    if (!uiPassword || !Number.isInteger(port) || port < 1 || port > 65535) {
      log('ui-network-config-invalid', { hasPassword: Boolean(uiPassword), port });
      process.exit(70);
    }

    // The native desktop reads this token when opening Local. Enabling its network password
    // without a local token locks the owning user out as well. Use the shipped auth runtime
    // before the server starts (appRunning above refuses concurrent store writers), not a
    // second token format or an unauthenticated loopback exemption.
    let localToken = '';
    let localAuthError = null;
    try {
      const { createRemoteClientAuthRuntime } = await import(
        pathToFileURL(localNetwork.clientAuthModule).href
      );
      const localAuth = createRemoteClientAuthRuntime({
        fsPromises: fsp, path, crypto,
        storePath: path.join(path.dirname(settingsPath), 'remote-clients.json'),
      });
      localToken = await withRetry(async () => {
        if (await localAuth.authenticateBearerToken(settings.desktopLocalClientToken)) {
          return settings.desktopLocalClientToken;
        }
        const issued = await localAuth.createClient({
          label: 'OpenChamber Desktop',
          clientKind: 'desktop-local',
          dedupeKey: 'desktop-local',
        });
        if (!issued?.token || !(await localAuth.authenticateBearerToken(issued.token))) {
          throw new Error('the issued local token is not accepted by the native store');
        }
        return issued.token;
      }, LOCAL_AUTH_ATTEMPTS, LOCAL_AUTH_RETRY_MS);
    } catch (error) {
      localAuthError = error;
    }

    if (localAuthError) {
      // Fail safe, not fatal: a password-protected listener without a working Local token locks
      // the owner out. Remove the LAN declaration for this run so the embedded engine starts on
      // loopback without a password, keep the user's other settings, and let the next start retry.
      // The log line is the evidence; this is not silently treated as configured.
      log('local-auth-unavailable-lan-disabled', {
        message: String(localAuthError?.message || localAuthError),
      });
      delete settings.desktopLanAccessEnabled;
      delete settings.desktopUiPassword;
      delete settings.desktopLocalPort;
      codes.add(6);
    } else {
      settings.desktopLanAccessEnabled = true;
      settings.desktopUiPassword = uiPassword;
      settings.desktopLocalPort = port;
      settings.desktopLocalClientToken = localToken;
      log('native-network-configured', { port, localClientToken: true });
    }
  }

  const hosts = Array.isArray(settings.desktopHosts) ? settings.desktopHosts.slice() : [];
  const desiredIds = new Set(desired.map((host) => host.id));
  const removeIds = new Set(previous.filter((id) => !desiredIds.has(id)));
  const nextHosts = hosts.filter((host) => host && !removeIds.has(host.id));
  const hostState = new Map();

  // Hosts are reconciled concurrently so one unreachable peer cannot add its whole budget to the
  // next. Every operation is bounded, so the stage finishes in about one host's worst case.
  const reconcileHost = async (host) => {
    const id = host.id;
    const url = normalizeUrl(host.url);
    if (!id || !url) {
      log('skip-invalid-host', { id });
      return null;
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
        hostState.set(id, 'unreachable');
        log('network-error-keep-token', { id });
      } else if (status !== 'valid') {
        hostState.set(id, 'unreachable');
        log('probe-unexpected-keep-token', { id, state: status });
      } else hostState.set(id, 'reachable');
    }

    if (needMint) {
      if (!host.mintCommand) {
        log('missing-mint-command', { id });
        hostState.set(id, 'unreachable');
        codes.add(3);
        // A configured host without a token is still listed; the app probes it and shows its own
        // unreachable state. Hiding it here would make an offline server look undeclared.
        token = '';
      }
      if (host.mintCommand) {
        const result = await mint(host.mintCommand);
        if (result.ok) {
          token = result.token;
          hostState.set(id, 'reachable');
          log('token-minted', { id });
        } else {
          token = '';
          hostState.set(id, 'unreachable');
          const denied = result.code === 'exit-77';
          log(denied ? 'bootstrap-denied-do-not-enroll' : 'mint-failed', {
            id,
            code: result.code,
            detail: result.detail,
          });
          if (denied) {
            if (existing) delete existing.clientToken;
            codes.add(4);
          } else {
            codes.add(5);
          }
        }
      }
    }

    return storedEntry({
      id,
      label: host.label || id,
      url: host.url,
      apiUrl: host.apiUrl,
      clientToken: token,
    });
  };

  const reconciled = await Promise.all(desired.map(reconcileHost));
  const reconciledById = new Map(
    reconciled.filter(Boolean).map((entry) => [entry.id, entry]),
  );
  const mergedHosts = nextHosts.map((entry) => (
    reconciledById.has(entry.id) ? { ...entry, ...reconciledById.get(entry.id) } : entry
  ));
  for (const entry of reconciled) {
    if (entry && !nextHosts.some((host) => host.id === entry.id)) mergedHosts.push(entry);
  }

  settings.desktopHosts = mergedHosts;
  // The default instance is the user's choice, not the registry's. Writing it on every start made
  // each restart select the remote server again. A first run may seed this machine's own entry;
  // an existing default is preserved, and one that points at a removed managed entry is repaired.
  if (
    typeof settings.desktopDefaultHostId === 'string'
    && removeIds.has(settings.desktopDefaultHostId)
  ) {
    delete settings.desktopDefaultHostId;
  }
  if (!settings.desktopDefaultHostId && registry.defaultHostId) {
    settings.desktopDefaultHostId = registry.defaultHostId;
  }

  await atomicWrite(settingsPath, settings);
  await atomicWrite(statePath, { ...state, previousManaged: [...desiredIds] });
  log('settings-written', {
    hosts: mergedHosts.length,
    defaultHostId: settings.desktopDefaultHostId ?? null,
    configured: mergedHosts.map((host) => host.id),
    reachable: [...hostState].filter(([, state]) => state === 'reachable').map(([id]) => id),
    unreachable: [...hostState].filter(([, state]) => state === 'unreachable').map(([id]) => id),
  });
  const exitCode = [4, 3, 5, 6].find((code) => codes.has(code)) ?? 0;
  process.exit(exitCode);
} catch (error) {
  log('adapter-error', { message: String(error?.message || error) });
  process.exit(70);
}
