// @ts-nocheck
// Unit tests for dsh-capability: P5 tenant isolation primitive + P6 audit log.
import { test } from 'node:test';
import assert from 'node:assert';
import { isolationPlan, execDecision } from '../lib/isolation.js';
import { toAuditRecord, serializeRecord, AuditRing, AUDIT_FIELD_ORDER } from '../lib/audit.js';

// ---- P5: tenant isolation ----

test('isolation: builds unshare -m -u argv for a tenant root', () => {
  const plan = isolationPlan({ tenantRoot: '/var/lib/dsh/tenants/t1', mounts: [] });
  assert.equal(plan.apply, true);
  assert.deepEqual(plan.argv.slice(0, 3), ['unshare', '--mount', '--uts']);
  assert.ok(plan.bindMasks.some((m) => m.source === '/etc'));
  assert.ok(plan.bindMasks.some((m) => m.source === '/home'));
});
test('isolation: refuses to isolate the whole filesystem (fail-closed)', () => {
  const plan = isolationPlan({ tenantRoot: '/', mounts: [] });
  assert.equal(plan.apply, false);
  assert.deepEqual(plan.argv, []);
});
test('isolation: refuses an empty tenant root', () => {
  assert.equal(isolationPlan({ tenantRoot: '', mounts: [] }).apply, false);
});
test('isolation: execDecision couples grant + isolation', () => {
  assert.equal(execDecision(false, { tenantRoot: '/var/lib/dsh/tenants/t1' }).allowed, false);
  const granted = execDecision(true, { tenantRoot: '/var/lib/dsh/tenants/t1' });
  assert.equal(granted.allowed, true);
  assert.equal(granted.isolation, true);
  // A whole-FS exec grant is allowed but NOT isolatable by this primitive.
  assert.equal(execDecision(true, { tenantRoot: '/' }).isolation, false);
});

// ---- P6: audit log (leak-free) ----

test('audit: toAuditRecord is leak-free (drops extra fields)', () => {
  const rec = toAuditRecord({
    principal: 'user:subA',
    resource: 'path:/etc/nixos',
    action: 'write',
    result: 'allow',
    reason: 'granted',
    authority: 'user:operator',
    // @ts-expect-error payload must be dropped
    payload: 'TOP-SECRET-CONTENT',
  });
  assert.equal(rec.payload, undefined);
  assert.equal(rec.authority, 'user:operator');
});
test('audit: serializeRecord emits only whitelisted fields in order', () => {
  const rec = toAuditRecord({
    principal: 'user:subA',
    resource: 'path:/etc/nixos',
    action: 'write',
    result: 'deny',
    reason: 'no grant',
    // @ts-expect-error must not survive
    content: 'secret',
  });
  const s = serializeRecord(rec);
  const parsed = JSON.parse(s);
  assert.equal(parsed.content, undefined);
  assert.deepEqual(Object.keys(parsed), ['at', 'principal', 'resource', 'action', 'result', 'reason']);
});
test('audit: AuditRing retains last N and supports snapshot', () => {
  const ring = new AuditRing(2);
  ring.push(toAuditRecord({ principal: 'user:a', resource: 'node:x', action: 'read', result: 'allow', reason: 'g' }));
  ring.push(toAuditRecord({ principal: 'user:b', resource: 'node:y', action: 'read', result: 'deny', reason: 'no grant' }));
  ring.push(toAuditRecord({ principal: 'user:c', resource: 'node:z', action: 'read', result: 'deny', reason: 'no grant' }));
  assert.equal(ring.snapshot().length, 2);
  assert.equal(ring.snapshot()[0].principal, 'user:b');
});
test('audit: field order is the stable whitelist', () => {
  assert.deepEqual(AUDIT_FIELD_ORDER, ['at', 'principal', 'resource', 'action', 'result', 'reason', 'authority', 'viaNode']);
});
