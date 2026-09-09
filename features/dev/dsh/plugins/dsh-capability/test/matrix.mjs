// @ts-nocheck
// dsh-capability verification-matrix runner.
//
// Exercises the built plugin's pure core against the impl-spec V-matrix rows
// (V1–V6, V11–V15) and prints PASS/FAIL for each. Run it against a BUILT plugin:
//   P=$(nix build .#dsh-capability --print-out-paths --no-link | tail -1)
//   DSH_CAPABILITY_LIB="$P/lib/node_modules/dsh-capability/lib" node test/matrix.mjs
//
// Exit code 0 = all pass. This is the fastest way to prove the *logic* greift
// without a live harness; see the README for the end-to-end (enforced) test.
import * as path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const libRoot = process.env.DSH_CAPABILITY_LIB
  ? path.resolve(process.env.DSH_CAPABILITY_LIB)
  : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'lib');
// On the Nix build the modules are plain ESM (.js) with relative specifiers; on
// a tsc-EMSM build they live directly in libRoot. Import the modules we test.
// (We re-import file paths rather than bare "./x.js" so the lib root is flexible.)
const load = async (m) => (await import(pathToFileURL(path.join(libRoot, m)).href));
const { authorise } = await load('authorise.js');
const { canonicalize, isWithinRoot } = await load('canonicalize.js');
const { createToken, attenuate, encodeToken, decodeToken } = await load('capability.js');
const { presetForClearance } = await load('presets.js');

const S = 'test-secret';
const now = Date.now();
const grant = (over) => createToken(S, {
  principal: 'user:subA',
  resources: ['path:/etc/nixos/**'],
  actions: ['read', 'write', 'mutate'],
  bounds: { ttl: now + 100000 },
  alg: 'hmac-sha256',
  ...over,
}).payload;

const A = (principal, resource, action, claims, groups) =>
  authorise({ principal, resource, action, claims, groups: groups ?? [] });

const results = new Map();
const check = (name, cond) => results.set(name, cond);

const g = grant();
// V1 default-deny
check('V1 default-deny', A('user:subA', 'path:/etc/nixos', 'read', []).allowed === false);
// V2 granted read
check('V2 granted read', A('user:subA', 'path:/etc/nixos/flake.nix', 'read', [g]).allowed === true);
// V3 granted write
check('V3 granted write', A('user:subA', 'path:/etc/nixos', 'write', [g]).allowed === true);
// V4 un-granted sibling
check('V4 sibling deny', A('user:subA', 'path:/home/philipp/x', 'write', [g]).allowed === false);
// V5 symlink escape (resolved to outside path)
check('V5 symlink escape deny', A('user:subA', 'path:/etc/passwd', 'read', [g]).allowed === false);
// V6 traversal condenses then fails grant match
check('V6 ../ condense deny', canonicalize('/etc/nixos/../outside') === '/etc/outside' && A('user:subA', 'path:/etc/nixos/../outside', 'read', [g]).allowed === false);
// V11 exec not granted
check('V11 exec denied', A('user:subA', 'path:/srv/media/a', 'exec', [grant({ actions: ['read'], resources: ['path:/srv/media/**'] })]).allowed === false);
// V12 non-widening attenuation refuses widen
check('V12 non-widening', (() => { try { attenuate(S, createToken(S, grant({ actions: ['read'] })), { actions: ['read', 'write'] }); return false; } catch { return true; } })());
// V13 expiry
check('V13 expired deny', A('user:subA', 'path:/etc/nixos', 'read', [grant({ bounds: { ttl: now - 10000 } })]).allowed === false);
// V14 cross-node: user grant not satisfied by node grant; node not authority
check('V14 node-not-authority', A('user:subF', 'path:/srv/public/x', 'read', [grant({ principal: 'node:strummer', resources: ['path:/srv/public/**'], actions: ['read'] })]).allowed === false);
// V15 single source of truth (same claims for read+exec share the policy)
const ge = grant({ actions: ['read', 'exec'], resources: ['path:/workspace/**'] });
check('V15 single policy', A('user:subA', 'path:/workspace/t', 'read', [ge]).allowed === true && A('user:subA', 'path:/workspace/t', 'exec', [ge]).allowed === true);
// prefix boundary safety
check('prefix boundary', isWithinRoot('/etc/nixos', '/etcd') === false && isWithinRoot('/etc/nixos', '/etc/nixos/foo') === true);
// P2 preset least-privilege
check('P2 preset Restricted', presetForClearance('Restricted').sandbox === 'read-only');
// token roundtrip
check('token roundtrip', decodeToken(S, encodeToken(createToken(S, grant()))).principal === 'user:subA');

let all = true;
for (const [name, cond] of results) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${name}`);
  if (!cond) all = false;
}
console.log(all ? 'ALL PASS' : 'SOME FAIL');
process.exit(all ? 0 : 1);
