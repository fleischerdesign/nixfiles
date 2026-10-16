import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { mergeManagedHosts, isManagedHost } from './managed-hosts.mjs';

test('managed intent merges without mutating settings and reloads credentials and removals', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'managed-hosts-'));
  try {
    const config = path.join(root, 'config.json');
    const state = path.join(root, 'state.json');
    const env = { OPENCHAMBER_MANAGED_HOSTS_CONFIG: config, OPENCHAMBER_MANAGED_HOSTS_STATE: state };
    const original = { hosts: [{ id: 'personal', url: 'http://personal:3000' }], defaultHostId: 'local' };
    fs.writeFileSync(config, JSON.stringify({ hosts: [{ name: 'server', url: 'http://server:3000' }] }));
    const offline = mergeManagedHosts(original, env);
    assert.equal(offline.hosts.length, 2);
    assert.equal(offline.hosts[1].clientToken, undefined);
    fs.writeFileSync(state, JSON.stringify({ connections: { server: { url: 'http://server:3000', token: 'first' } } }));
    assert.equal(mergeManagedHosts(original, env).hosts[1].clientToken, 'first');
    fs.writeFileSync(state, JSON.stringify({ connections: { server: { url: 'http://server:3000', token: 'renewed' } } }));
    assert.equal(mergeManagedHosts(original, env).hosts[1].clientToken, 'renewed');
    assert.equal(original.hosts.length, 1);
    assert.equal(isManagedHost(offline.hosts[1]), true);
    fs.writeFileSync(config, JSON.stringify({ hosts: [{ name: 'server', url: 'http://changed:3000' }] }));
    assert.equal(mergeManagedHosts(original, env).hosts[1].clientToken, undefined);
    fs.writeFileSync(config, JSON.stringify({ hosts: [] }));
    assert.deepEqual(mergeManagedHosts({ ...original, defaultHostId: 'nix:server' }, env).hosts, original.hosts);
    assert.equal(mergeManagedHosts({ ...original, defaultHostId: 'nix:server' }, env).defaultHostId, 'local');
    fs.writeFileSync(config, JSON.stringify({ hosts: [{ name: 'server', url: 'http://server:3000' }] }));
    fs.writeFileSync(state, 'corrupt');
    assert.throws(() => mergeManagedHosts(original, env), SyntaxError);
    fs.unlinkSync(config);
    assert.deepEqual(mergeManagedHosts(original, env).hosts, original.hosts);
    assert.equal(mergeManagedHosts(original, {}), original);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('active managed runtime adopts a renewed token in place and keeps other runtimes untouched', async () => {
  const { refreshManagedRuntime } = await import('./managed-runtime.mjs');
  let token = 'old';
  const calls = [];
  const dependencies = {
    readHosts: async () => ({ hosts: [{ id: 'nix:server', url: 'http://server:3000/', clientToken: 'new' }] }),
    readUrl: () => 'http://server:3000', readToken: () => token,
    setToken: value => { token = value; calls.push('token'); },
    refreshUrlToken: async url => { assert.equal(url, 'http://server:3000'); calls.push('url-token'); },
    resume: () => calls.push('resume'),
  };
  await assert.rejects(refreshManagedRuntime({ ...dependencies, refreshUrlToken: async () => { throw new Error('offline'); } }), /offline/);
  assert.equal(token, 'old');
  calls.length = 0;
  assert.equal(await refreshManagedRuntime(dependencies), true);
  assert.deepEqual(calls, ['token', 'url-token', 'resume']);
  assert.equal(await refreshManagedRuntime(dependencies), false);
  assert.equal(await refreshManagedRuntime({ ...dependencies, readUrl: () => 'http://other:3000' }), false);
  assert.equal(await refreshManagedRuntime({ ...dependencies, readHosts: async () => ({ hosts: [] }) }), false);
});
