// Exercise the installed application, including packaged-mode resource paths,
// Chromium sandbox setup, preload bridge and the project browser's real API.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { spawn } from 'node:child_process';

const work = fs.mkdtempSync(path.join(process.env.TMPDIR, 'openchamber-gui-'));
const home = path.join(work, 'home');
const fixture = path.join(work, 'project outside home');
fs.mkdirSync(home);
fs.mkdirSync(fixture);
fs.writeFileSync(path.join(fixture, 'project-marker'), 'native filesystem');
const project = process.argv[3] || fixture;
const marker = process.argv[3] ? 'flake.nix' : 'project-marker';
const managedConfig = path.join(work, 'managed-config.json');
const managedState = path.join(work, 'managed-state.json');
const managedPeer = { name: 'mesh-peer', url: 'http://127.0.0.1:9' };
fs.writeFileSync(managedConfig, JSON.stringify({ hosts: [managedPeer] }));
fs.writeFileSync(managedState, JSON.stringify({ connections: {} }));
const listener = net.createServer();
await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
const port = listener.address().port;
await new Promise(resolve => listener.close(resolve));
const logPath = path.join(work, 'application.log');
const log = fs.openSync(logPath, 'w');
const child = spawn('xvfb-run', [
  '-a', '--server-args=-screen 0 1440x1000x24', process.argv[2],
  '--ozone-platform=x11', '--disable-gpu', '--lang=en-US', `--remote-debugging-port=${port}`,
], {
  cwd: home,
  env: {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: path.join(home, '.config'),
    XDG_DATA_HOME: path.join(home, '.local/share'),
    XDG_CACHE_HOME: path.join(home, '.cache'),
    XDG_STATE_HOME: path.join(home, '.local/state'),
    OPENCHAMBER_DESKTOP_USER_DATA_DIR: path.join(home, 'profile'),
    OPENCHAMBER_MANAGED_HOSTS_CONFIG: managedConfig,
    OPENCHAMBER_MANAGED_HOSTS_STATE: managedState,
    OPENCODE_SKIP_START: process.env.OPENCHAMBER_TEST_OPENCODE_BINARY ? 'false' : 'true',
    OPENCODE_BINARY: process.env.OPENCHAMBER_TEST_OPENCODE_BINARY || '',
    OPENCHAMBER_RELAY_HOST: 'off',
    WAYLAND_DISPLAY: '',
  },
  stdio: ['ignore', log, log],
  detached: true,
});
const pending = new Map();
let socket;
let requestId = 0;
const pause = () => new Promise(resolve => setTimeout(resolve, 500));
const deadline = Date.now() + 60000;
const watchdog = setTimeout(() => {
  console.error('GUI test timed out', fs.readFileSync(logPath, 'utf8'));
  try { process.kill(-child.pid, 'SIGTERM'); } catch {}
  process.exit(1);
}, 65000);

try {
  let target;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`Application exited: ${child.exitCode}`);
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = targets.find(entry => entry.type === 'page' && entry.url.startsWith('openchamber-ui:'));
      if (target) break;
    } catch {}
    await pause();
  }
  assert.ok(target, 'Packaged renderer did not start');
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (!message.id) return;
    const request = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++requestId;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const expression = `(async () => {
    const base = window.__OPENCHAMBER_API_BASE_URL__ || window.__OPENCHAMBER_LOCAL_ORIGIN__;
    if (!base || !document.querySelector('#root')?.childElementCount || !/Welcome to OpenChamber|New session|New chat/.test(document.body.innerText)) return { ready: false };
    const headers = { ...window.__OPENCHAMBER_RUNTIME_HEADERS__ };
    if (window.__OPENCHAMBER_CLIENT_TOKEN__) headers.Authorization = 'Bearer ' + window.__OPENCHAMBER_CLIENT_TOKEN__;
    const list = async directory => {
      const response = await fetch(base + '/api/fs/list?path=' + encodeURIComponent(directory), { headers });
      if (!response.ok) throw new Error(response.status + ' ' + await response.text());
      return response.json();
    };
    if (${Boolean(process.env.OPENCHAMBER_TEST_OPENCODE_BINARY)}) {
      const health = await fetch(base + '/api/opencode/health', { headers });
      if (!health.ok || !(await health.json()).healthy || !/New session|New chat/.test(document.body.innerText)) return { ready: false };
    }
    const parent = await list(${JSON.stringify(path.dirname(project))});
    const project = await list(${JSON.stringify(project)});
    const update = await window.__OPENCHAMBER_DESKTOP__.invoke('desktop_check_for_updates');
    let installError = '';
    try { await window.__OPENCHAMBER_DESKTOP__.invoke('desktop_download_and_install_update'); }
    catch (error) { installError = String(error); }
    return {
      ready: true, url: location.href, title: document.title,
      body: document.body.innerText.slice(0, 400),
      parent: parent.entries.find(entry => entry.path === ${JSON.stringify(project)}),
      marker: project.entries.find(entry => entry.name === ${JSON.stringify(marker)}),
      update, installError,
    };
  })()`;
  let result;
  while (Date.now() < deadline) {
    result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (!result.exceptionDetails && result.result.value?.ready) break;
    await pause();
  }
  if (result?.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  const value = result?.result.value;
  assert.ok(value?.ready, 'React application and preload bridge did not become ready');
  assert.equal(value.parent?.path, project);
  assert.equal(value.parent?.isDirectory, true);
  assert.equal(value.marker?.path, path.join(project, marker));
  assert.equal(value.update.available, false);
  assert.match(value.installError, /updates are managed by Nix/);
  const invoke = async (command, args = {}) => {
    const result = await send('Runtime.evaluate', {
      expression: `window.__OPENCHAMBER_DESKTOP__.invoke(${JSON.stringify(command)}, ${JSON.stringify(args)})`,
      awaitPromise: true, returnByValue: true,
    });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  let hosts = await invoke('desktop_hosts_get');
  assert.equal(hosts.hosts.find(host => host.id === 'nix:mesh-peer')?.url, managedPeer.url);
  assert.equal(hosts.hosts.find(host => host.id === 'nix:mesh-peer')?.clientToken, undefined);
  const writeCredentials = token => fs.writeFileSync(managedState, JSON.stringify({
    connections: { 'mesh-peer': { url: managedPeer.url, token } },
  }));
  writeCredentials('managed-test-token');
  hosts = await invoke('desktop_hosts_get');
  assert.equal(hosts.hosts.find(host => host.id === 'nix:mesh-peer')?.clientToken, 'managed-test-token');
  writeCredentials('renewed-test-token');
  hosts = await invoke('desktop_hosts_get');
  assert.equal(hosts.hosts.find(host => host.id === 'nix:mesh-peer')?.clientToken, 'renewed-test-token');
  await invoke('desktop_hosts_set', { input: {
    hosts: [...hosts.hosts, { id: 'manual', label: 'Personal', url: 'http://127.0.0.1:8' }],
    defaultHostId: 'local', initialHostChoiceCompleted: true,
  } });
  const saved = JSON.parse(fs.readFileSync(path.join(home, '.config/openchamber/settings.json'), 'utf8'));
  assert.ok(saved.desktopHosts.some(host => host.id === 'manual'));
  assert.ok(!saved.desktopHosts.some(host => host.id.startsWith('nix:')));
  assert.ok(!JSON.stringify(saved).includes('renewed-test-token'));
  fs.writeFileSync(managedConfig, JSON.stringify({ hosts: [] }));
  hosts = await invoke('desktop_hosts_get');
  assert.ok(!hosts.hosts.some(host => host.id.startsWith('nix:')));
  assert.ok(hosts.hosts.some(host => host.id === 'manual'));
  console.log('ok: managed hosts, live token renewal, removal and mutable-settings isolation');
  if (process.env.OPENCHAMBER_TEST_SCREENSHOT) {
    const screenshot = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(process.env.OPENCHAMBER_TEST_SCREENSHOT, Buffer.from(screenshot.data, 'base64'));
  }
  console.log('ok: graphical startup, packaged UI, project browser and Nix-managed updates');
  console.log(JSON.stringify(value));
} catch (error) {
  console.error(fs.readFileSync(logPath, 'utf8'));
  throw error;
} finally {
  clearTimeout(watchdog);
  socket?.close();
  try { process.kill(-child.pid, 'SIGTERM'); } catch {}
  fs.closeSync(log);
}
