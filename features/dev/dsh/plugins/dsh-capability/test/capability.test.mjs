// @ts-nocheck
// Unit tests for the dsh-capability pure core. These exercise the matrix rows
// (V1–V15) at the primitive level. Run against the compiled lib via:
//   node --test test/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert';
import { canonicalize, isWithinRoot, compileRoot } from '../lib/canonicalize.js';
import { createToken, verifyToken, attenuate, encodeToken, decodeToken, pathResourceToRoot } from '../lib/capability.js';
import { authorise, attributionFromDelegation } from '../lib/authorise.js';
import { CapabilityError } from '../lib/error.js';

const SECRET = 'test-secret';
const now = Date.now();
const cap = (over) => createToken(SECRET, {
  principal: 'user:subA',
  resources: ['path:/etc/nixos/**'],
  actions: ['read', 'write', 'mutate'],
  bounds: { ttl: now + 100000 },
  alg: 'hmac-sha256',
  ...over,
}).payload;

test('canonicalize: V6 rejects absolute .. that pops the mount root', () => {
  assert.throws(() => canonicalize('/../../etc'), CapabilityError);
  assert.throws(() => canonicalize('/etc/../../tmp'), CapabilityError);
  assert.throws(() => canonicalize('/..'), CapabilityError);
});
test('authorise: V6 ../ inside path condenses then fails the grant match (deny)', () => {
  assert.equal(canonicalize('/etc/nixos/../outside'), '/etc/outside');
  const d = authorise({ principal: 'user:subA', resource: 'path:/etc/nixos/../outside', action: 'read', claims: [cap()] });
  assert.equal(d.allowed, false);
});
test('canonicalize: condenses legal .. and .', () => {
  assert.equal(canonicalize('/a/b/../c/./d'), '/a/c/d');
  assert.equal(canonicalize('/etc//nixos/'), '/etc/nixos');
});
test('canonicalize: rejects NUL and control bytes', () => {
  assert.throws(() => canonicalize('/etc\0/passwd'), CapabilityError);
  assert.throws(() => canonicalize('/etc/\x1fpasswd'), CapabilityError);
});
test('canonicalize: rejects relative and empty paths', () => {
  assert.throws(() => canonicalize('etc/nixos'), CapabilityError);
  assert.throws(() => canonicalize(''), CapabilityError);
});
test('isWithinRoot: boundary safety (V4 sibling)', () => {
  assert.equal(isWithinRoot('/etc/nixos', '/etc/nixos'), true);
  assert.equal(isWithinRoot('/etc/nixos', '/etc/nixos/foo'), true);
  assert.equal(isWithinRoot('/etc/nixos', '/etc'), false);
  assert.equal(isWithinRoot('/etc/nixos', '/etcd'), false);
  assert.equal(isWithinRoot('/etc/nixos', '/etc/nixos2'), false);
});
test('compileRoot: prefix automaton', () => {
  const m = compileRoot('/etc/nixos');
  assert.equal(m('/etc/nixos/foo/bar'), true);
  assert.equal(m('/etc/nixos'), true);
  assert.equal(m('/etc/nixoses'), false);
});
test('pathResourceToRoot: strips ** and rejects other globs', () => {
  assert.equal(pathResourceToRoot('path:/etc/nixos/**'), '/etc/nixos');
  assert.equal(pathResourceToRoot('path:/srv/media'), '/srv/media');
  assert.throws(() => pathResourceToRoot('path:/etc/*ixos'), CapabilityError);
});

// ---- authorise (V1, V2, V3, V4, V5, V11, V12, V13, V15) ----

test('authorise: V1 default-deny (no grant)', () => {
  const d = authorise({ principal: 'user:subA', resource: 'path:/etc/nixos', action: 'read', claims: [] });
  assert.equal(d.allowed, false);
  assert.equal(d.reason, 'deny');
});
test('authorise: V2 granted read allow', () => {
  const d = authorise({ principal: 'user:subA', resource: 'path:/etc/nixos/flake.nix', action: 'read', claims: [cap()] });
  assert.equal(d.allowed, true);
});
test('authorise: V3 granted write allow', () => {
  const d = authorise({ principal: 'user:subA', resource: 'path:/etc/nixos', action: 'write', claims: [cap()] });
  assert.equal(d.allowed, true);
});
test('authorise: V4 un-granted sibling deny', () => {
  const d = authorise({ principal: 'user:subA', resource: 'path:/home/philipp/secret', action: 'write', claims: [cap()] });
  assert.equal(d.allowed, false);
});
test('authorise: V5 symlink escape deny (resolved to outside path)', () => {
  const d = authorise({ principal: 'user:subA', resource: 'path:/etc/passwd', action: 'read', claims: [cap()] });
  assert.equal(d.allowed, false);
});
test('authorise: action not granted denies (V11 read-only vs exec)', () => {
  const readOnly = cap({ actions: ['read'], resources: ['path:/srv/media/**'] });
  assert.equal(authorise({ principal: 'user:subA', resource: 'path:/srv/media/a', action: 'read', claims: [readOnly] }).allowed, true);
  assert.equal(authorise({ principal: 'user:subA', resource: 'path:/srv/media/a', action: 'exec', claims: [readOnly] }).allowed, false);
});
test('authorise: wrong principal denies (no implicit inheritance)', () => {
  const d = authorise({ principal: 'user:subB', resource: 'path:/etc/nixos', action: 'read', claims: [cap()] });
  assert.equal(d.allowed, false);
});
test('authorise: group grant dominates via membership', () => {
  const g = cap({ principal: 'group:family', resources: ['path:/srv/media/**'], actions: ['read'] });
  assert.equal(authorise({ principal: 'user:subF', groups: ['family'], resource: 'path:/srv/media/x', action: 'read', claims: [g] }).allowed, true);
  assert.equal(authorise({ principal: 'user:subF', groups: [], resource: 'path:/srv/media/x', action: 'read', claims: [g] }).allowed, false);
});
test('authorise: expired grant denies (V13)', () => {
  const expired = cap({ bounds: { ttl: now - 10000 } });
  assert.equal(authorise({ principal: 'user:subA', resource: 'path:/etc/nixos', action: 'read', claims: [expired] }).allowed, false);
});
test('authorise: V15 single source of truth — same claims for read+exec', () => {
  const g = cap({ actions: ['read', 'exec'], resources: ['path:/workspace/**'] });
  for (const action of ['read', 'exec']) {
    assert.equal(authorise({ principal: 'user:subA', resource: 'path:/workspace/t', action, claims: [g] }).allowed, true);
  }
});

// ---- attenuation (V12 non-widening) ----

test('attenuate: narrows without widening (V12)', () => {
  const parent = createToken(SECRET, cap());
  const child = attenuate(SECRET, parent, {
    actions: ['read'],
    resources: ['path:/etc/nixos/hosts/**'],
    bounds: { ttl: now + 50000 },
  }).payload;
  assert.equal(authorise({ principal: 'user:subA', resource: 'path:/etc/nixos/hosts/yorke', action: 'read', claims: [child] }).allowed, true);
  assert.equal(authorise({ principal: 'user:subA', resource: 'path:/var', action: 'read', claims: [child] }).allowed, false);
});
test('attenuate: refuses resource widening', () => {
  const parent = createToken(SECRET, cap({ resources: ['path:/etc/nixos/**'] }));
  assert.throws(() => attenuate(SECRET, parent, { resources: ['path:/'] }), CapabilityError);
});
test('attenuate: refuses action widening', () => {
  const parent = createToken(SECRET, cap({ actions: ['read'] }));
  assert.throws(() => attenuate(SECRET, parent, { actions: ['read', 'write'] }), CapabilityError);
});
test('attenuate: refuses ttl widening', () => {
  const parent = createToken(SECRET, cap({ bounds: { ttl: now + 10000 } }));
  assert.throws(() => attenuate(SECRET, parent, { bounds: { ttl: now + 99999999 } }), CapabilityError);
});

// ---- token roundtrip + cross-node attribution (V14) ----

test('token: encode/decode roundtrip', () => {
  const t = createToken(SECRET, cap());
  const claims = decodeToken(SECRET, encodeToken(t));
  assert.equal(claims.principal, 'user:subA');
  assert.ok(claims.resources.includes('path:/etc/nixos/**'));
});
test('attributionFromDelegation: extracts user principal from a delegation token', () => {
  const t = createToken(SECRET, {
    principal: 'user:subFriend',
    resources: ['path:/srv/public/**'],
    actions: ['read'],
    bounds: { ttl: now + 100000 },
    alg: 'hmac-sha256',
    sink: 'node:strummer',
  });
  const att = attributionFromDelegation(SECRET, encodeToken(t));
  assert.equal(att.principal, 'user:subFriend');
});
test('attributionFromDelegation: null on malformed/no token', () => {
  assert.equal(attributionFromDelegation(SECRET, undefined), null);
  assert.equal(attributionFromDelegation(SECRET, 'garbage'), null);
});
test('cross-node: only the USER capability is evaluated, node channel is not authority (V14)', () => {
  const userGrant = cap({ principal: 'user:subFriend', resources: ['path:/srv/public/**'], actions: ['read'] });
  const nodeGrant = cap({ principal: 'node:strummer', resources: ['path:/srv/public/**'], actions: ['read'] });
  assert.equal(authorise({ principal: 'user:subFriend', resource: 'path:/srv/public/x', action: 'read', claims: [userGrant] }).allowed, true);
  assert.equal(authorise({ principal: 'user:subFriend', resource: 'path:/srv/public/x', action: 'read', claims: [nodeGrant] }).allowed, false);
});
