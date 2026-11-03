import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [adapter, runtimeModule] = process.argv.slice(2);
const { createRemoteClientAuthRuntime } = await import(pathToFileURL(runtimeModule).href);
const root = await fs.mkdtemp(path.join(os.tmpdir(), 'openchamber-local-auth-'));
try {
  const settingsPath = path.join(root, 'settings.json');
  const storePath = path.join(root, 'remote-clients.json');
  const registryPath = path.join(root, 'registry.json');
  const passwordPath = path.join(root, 'password');
  await fs.writeFile(passwordPath, 'fixture-only-password', { mode: 0o600 });
  await fs.writeFile(settingsPath, JSON.stringify({ desktopDefaultHostId: 'local', custom: 'preserved' }));
  await fs.writeFile(registryPath, JSON.stringify({
    hosts: [], localNetwork: { enable: true, port: 7337, uiPasswordFile: passwordPath, clientAuthModule: runtimeModule },
  }));
  const auth = () => createRemoteClientAuthRuntime({ fsPromises: fs, path, crypto, storePath });
  const foreign = await auth().createClient({ label: 'Existing peer', dedupeKey: 'peer' });
  const run = () => {
    const result = spawnSync(process.execPath, [adapter,
      '--registry', registryPath, '--state', path.join(root, 'state.json'),
      '--settings', settingsPath, '--app-user-data', path.join(root, 'app'),
    ], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  };
  const readSettings = async () => JSON.parse(await fs.readFile(settingsPath, 'utf8'));
  run();
  const first = await readSettings();
  assert.ok(first.desktopLocalClientToken, 'protected Local must have its native client token');
  assert.equal(first.desktopDefaultHostId, 'local');
  assert.equal(first.custom, 'preserved');
  assert.equal(first.desktopLanAccessEnabled, true);
  const localClient = await auth().authenticateBearerToken(first.desktopLocalClientToken);
  assert.ok(localClient, 'the native server must accept the delivered local token');
  assert.ok(await auth().authenticateBearerToken(foreign.token), 'peer token must survive');
  run();
  assert.equal((await readSettings()).desktopLocalClientToken, first.desktopLocalClientToken, 'restart must not rotate a valid local token');
  assert.equal((await auth().revokeClient(localClient.clientId)).revoked, true);
  run();
  const repaired = await readSettings();
  assert.notEqual(repaired.desktopLocalClientToken, first.desktopLocalClientToken);
  assert.ok(await auth().authenticateBearerToken(repaired.desktopLocalClientToken), 'revoked local token must be repaired');
  assert.ok(await auth().authenticateBearerToken(foreign.token), 'repair must preserve peer token');
  assert.equal((await fs.stat(settingsPath)).mode & 0o777, 0o600);
  assert.equal((await fs.stat(storePath)).mode & 0o777, 0o600);
  console.log('Local auth: native token accepted, restart stable, revocation repaired, peer preserved, files private');
} finally {
  await fs.rm(root, { recursive: true, force: true });
}
