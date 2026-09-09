// @ts-nocheck
// Unit tests for dsh-capability: P2 preset mapping + P1 fail-closed tool gate.
import { test } from 'node:test';
import assert from 'node:assert';
import { presetForClearance, buildPresetTable } from '../lib/presets.js';
import { extractResource, gateDecision } from '../lib/toolgate.js';

const PATH_TOOLS = ['read', 'write', 'edit', 'glob', 'bash'];

// ---- P2: clearance → preset (least privilege) ----

test('preset: Admin ⇒ danger-full-access + never', () => {
  assert.deepEqual(presetForClearance('Admin'), { name: 'danger-full-access', sandbox: 'danger-full-access', approval: 'never' });
});
test('preset: Member ⇒ workspace-write + ask', () => {
  assert.deepEqual(presetForClearance('Member'), { name: 'workspace-write', sandbox: 'workspace-write', approval: 'ask' });
});
test('preset: Restricted ⇒ read-only + ask', () => {
  assert.deepEqual(presetForClearance('Restricted'), { name: 'read-only', sandbox: 'read-only', approval: 'ask' });
});
test('preset: unknown/undefined clearance fail-locks to Restricted (never widening)', () => {
  assert.deepEqual(presetForClearance(undefined), presetForClearance('Restricted'));
  assert.deepEqual(presetForClearance('superadmin'), presetForClearance('Restricted'));
});
test('preset: buildPresetTable honors operator overrides', () => {
  const t = buildPresetTable({ Member: { name: 'workspace-write', sandbox: 'workspace-write', approval: 'always' } });
  assert.equal(t.presets.Member.approval, 'always');
  assert.equal(t.presets.Admin.approval, 'never'); // untouched default
});

// ---- P1 tool gate: resource extraction (fail-closed) ----

test('toolgate: explicit exec.resource wins', () => {
  assert.equal(extractResource({ name: 'read', resource: 'path:/etc/nixos' }, PATH_TOOLS), 'path:/etc/nixos');
});
test('toolgate: raw args.path/file/target', () => {
  assert.equal(extractResource({ name: 'read', args: { path: '/etc/nixos/flake.nix' } }, PATH_TOOLS), 'path:/etc/nixos/flake.nix');
  assert.equal(extractResource({ name: 'write', args: { file: '/tmp/x' } }, PATH_TOOLS), 'path:/tmp/x');
});
test('toolgate: path list (glob) takes first element', () => {
  assert.equal(extractResource({ name: 'glob', args: { paths: ['/a', '/b'] } }, PATH_TOOLS), 'path:/a');
});
test('toolgate: non-path tool returns null (not gated)', () => {
  assert.equal(extractResource({ name: 'memory_query', args: { subject: 'x' } }, PATH_TOOLS), null);
});
test('toolgate: path tool with no determinable path is NOT authorizable (fail-closed)', () => {
  const d = gateDecision({ name: 'read', args: { content: 'no-path' } }, PATH_TOOLS);
  assert.equal(d.authorizable, false);
  assert.equal(d.resource, null);
});
test('toolgate: full gateDecision allow path', () => {
  const d = gateDecision({ name: 'bash', args: { cmd: 'ls', target: '/workspace' } }, PATH_TOOLS);
  assert.equal(d.authorizable, true);
  assert.equal(d.resource, 'path:/workspace');
});
