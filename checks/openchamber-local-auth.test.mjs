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
    return result;
  };
  const runOk = () => {
    const result = run();
    assert.equal(result.status, 0, result.stderr);
  };
  const readSettings = async () => JSON.parse(await fs.readFile(settingsPath, 'utf8'));
  runOk();
  const first = await readSettings();
  assert.ok(first.desktopLocalClientToken, 'protected Local must have its native client token');
  assert.equal(first.desktopDefaultHostId, 'local');
  assert.equal(first.custom, 'preserved');
  assert.equal(first.desktopLanAccessEnabled, true);
  const localClient = await auth().authenticateBearerToken(first.desktopLocalClientToken);
  assert.ok(localClient, 'the native server must accept the delivered local token');
  assert.ok(await auth().authenticateBearerToken(foreign.token), 'peer token must survive');
  runOk();
  assert.equal((await readSettings()).desktopLocalClientToken, first.desktopLocalClientToken, 'restart must not rotate a valid local token');
  assert.equal((await auth().revokeClient(localClient.clientId)).revoked, true);
  runOk();
  const repaired = await readSettings();
  assert.notEqual(repaired.desktopLocalClientToken, first.desktopLocalClientToken);
  assert.ok(await auth().authenticateBearerToken(repaired.desktopLocalClientToken), 'revoked local token must be repaired');
  assert.ok(await auth().authenticateBearerToken(foreign.token), 'repair must preserve peer token');
  assert.equal((await fs.stat(settingsPath)).mode & 0o777, 0o600);
  assert.equal((await fs.stat(storePath)).mode & 0o777, 0o600);

  // A broken auth store must not be masked: the protected listener is removed for this run so the
  // embedded engine starts on loopback and Local stays usable, the failure is reported as exit 6,
  // and the next start can retry. The user's settings and the last valid token are preserved.
  const brokenModule = path.join(root, 'broken-auth.mjs');
  await fs.writeFile(brokenModule, `
    export const createRemoteClientAuthRuntime = () => {
      throw new Error('fixture: client-auth store unavailable');
    };
  `);
  await fs.writeFile(registryPath, JSON.stringify({
    hosts: [],
    localNetwork: { enable: true, port: 7337, uiPasswordFile: passwordPath, clientAuthModule: brokenModule },
  }));
  const failed = run();
  assert.equal(failed.status, 6, failed.stderr);
  assert.match(failed.stderr, /local-auth-unavailable-lan-disabled/);
  const afterFailure = await readSettings();
  assert.equal(afterFailure.desktopLanAccessEnabled, undefined, 'a password-protected listener must not start without a Local token');
  assert.equal(afterFailure.desktopUiPassword, undefined);
  assert.equal(afterFailure.desktopLocalPort, undefined);
  assert.equal(afterFailure.desktopLocalClientToken, repaired.desktopLocalClientToken, 'the failure must not discard the last valid token');
  assert.equal(afterFailure.custom, 'preserved');
  assert.equal(afterFailure.desktopMinimizeToTrayEnabled, true);
  console.log('Local auth: native token accepted, restart stable, revocation repaired, peer preserved, files private');
} finally {
  await fs.rm(root, { recursive: true, force: true });
}
