// Acceptance for the client adapter: real server token, real settings file, atomic write, and the
// two failure paths that decide whether a device may open a window (denied grant, running app).
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const [bin, mintBin, adapter, nodeBin] = process.argv.slice(2);
if (!bin || !mintBin || !adapter || !nodeBin) {
  throw new Error('usage: openchamber-provision.test.mjs <server> <mint> <adapter> <node>');
}

const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'oc-provision-'));
const dataDir = path.join(root, 'data');
const allowlist = path.join(root, 'bootstrap-devices');
const passwordFile = path.join(root, 'password');
const mintConfig = path.join(root, 'mint.json');
const settingsPath = path.join(root, 'config', 'openchamber', 'settings.json');
const statePath = path.join(root, 'state', 'state.json');
const registryPath = path.join(root, 'registry.json');
const appUserData = path.join(root, 'userData');
const password = `dummy-${crypto.randomBytes(8).toString('hex')}`;
const port = 39000 + Math.floor(Math.random() * 1000);
const base = `http://127.0.0.1:${port}`;

await fsp.mkdir(dataDir, { recursive: true });
await fsp.mkdir(appUserData, { recursive: true });
await fsp.mkdir(path.dirname(settingsPath), { recursive: true });
await fsp.writeFile(passwordFile, `${password}\n`, { mode: 0o600 });
await fsp.writeFile(allowlist, 'hom-wrk-01\n', { mode: 0o644 });
await fsp.writeFile(
  mintConfig,
  JSON.stringify({ serverUrl: base, passwordFile, allowlistFile: allowlist }),
  { mode: 0o600 },
);
await fsp.writeFile(
  registryPath,
  JSON.stringify({
    hosts: [
      {
        id: 'cld-ops-01',
        label: 'cld-ops-01',
        url: base,
        apiUrl: base,
        mintCommand: `OPENCHAMBER_MINT_CONFIG=${mintConfig} ${mintBin} hom-wrk-01`,
      },
    ],
    defaultHostId: 'cld-ops-01',
  }),
);
await fsp.writeFile(
  settingsPath,
  JSON.stringify({
    theme: 'dark',
    desktopHosts: [{ id: 'manual-host', label: 'manual', url: 'https://example.invalid' }],
    desktopDefaultHostId: 'manual-host',
    desktopWindowState: { width: 1200 },
  }),
  { mode: 0o600 },
);

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

const runAdapter = () =>
  new Promise((resolve) => {
    const child = spawn(
      nodeBin,
      [adapter, '--registry', registryPath, '--state', statePath, '--settings', settingsPath, '--app-user-data', appUserData],
      { env: { ...process.env }, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let err = '';
    child.stderr.on('data', (chunk) => {
      err += chunk.toString();
    });
    child.once('exit', (code) => resolve({ code, err: err.trim() }));
  });

const readSettings = async () => JSON.parse(await fsp.readFile(settingsPath, 'utf8'));

try {
  await start();

  const first = await runAdapter();
  const afterFirst = await readSettings();
  const managed = afterFirst.desktopHosts.find((host) => host.id === 'cld-ops-01');
  const manual = afterFirst.desktopHosts.find((host) => host.id === 'manual-host');
  const mode = (await fsp.stat(settingsPath)).mode & 0o777;
  record('first-provision-writes-token', first.code === 0 && /^oc_client_/.test(managed?.clientToken || ''), {
    code: first.code,
  });
  record('preserves-unmanaged', Boolean(manual) && afterFirst.theme === 'dark' && afterFirst.desktopWindowState?.width === 1200);
  record(
    'preserves-user-default-not-registry-default',
    afterFirst.desktopDefaultHostId === 'manual-host',
    { defaultHostId: afterFirst.desktopDefaultHostId },
  );
  record('atomic-mode-0600', mode === 0o600, { mode: mode.toString(8) });

  const token = managed.clientToken;
  const second = await runAdapter();
  const afterSecond = await readSettings();
  record(
    'second-run-does-not-rotate',
    second.code === 0 && afterSecond.desktopHosts.find((host) => host.id === 'cld-ops-01')?.clientToken === token,
    { code: second.code },
  );

  // Denied grant: the adapter must not enroll and must not leave a token behind.
  const withoutToken = { ...afterSecond };
  withoutToken.desktopHosts = afterSecond.desktopHosts.map((host) =>
    host.id === 'cld-ops-01' ? { ...host, clientToken: undefined } : host,
  );
  await fsp.writeFile(settingsPath, JSON.stringify(withoutToken, null, 2), { mode: 0o600 });
  await fsp.writeFile(allowlist, '', { mode: 0o644 });
  const denied = await runAdapter();
  const afterDenied = await readSettings();
  record(
    'denied-grant-fails-closed',
    denied.code === 4 && !afterDenied.desktopHosts.find((host) => host.id === 'cld-ops-01')?.clientToken,
    { code: denied.code },
  );

  // A live SingletonLock means the app owns the profile; the adapter must not rewrite settings.
  await fsp.writeFile(allowlist, 'hom-wrk-01\n', { mode: 0o644 });
  const before = await fsp.readFile(settingsPath, 'utf8');
  await fsp.symlink(`${os.hostname()}-${process.pid}`, path.join(appUserData, 'SingletonLock'));
  const running = await runAdapter();
  const after = await fsp.readFile(settingsPath, 'utf8');
  record('running-app-defers', running.code === 75 && before === after, { code: running.code });
} finally {
  if (server && server.exitCode === null) {
    server.kill('SIGTERM');
    await Promise.race([new Promise((resolve) => server.once('exit', resolve)), sleep(5000)]);
  }
  await fsp.rm(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }).catch(() => {});
}

const failed = results.filter((result) => !result.ok);
console.log(JSON.stringify({ summary: { total: results.length, failed: failed.length } }));
process.exit(failed.length === 0 ? 0 : 1);
