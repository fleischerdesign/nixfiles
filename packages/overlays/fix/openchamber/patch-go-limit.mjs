// Teach OpenChamber's limit failover about OpenCode Go's own limit error type.
//
// OpenCode reports a Go plan whose window is spent as `provider.go-limit`. OpenChamber 2.6.0 lists
// the other five limit types in two independent boundaries - `policy.js` (the server-side
// classifier) and the generated `PLUGIN_SOURCE` in `runtime.js` (the retry hook that decides
// whether to report the failure at all) - and neither contains it, so a Go limit ends the session
// instead of switching to the next credential.
//
// This is a compatibility patch, not a feature: it adds the one type to both sets and keeps the
// native account switching that upstream already implements. It is tied to the pinned 2.6.0
// sources and fails closed when that no longer describes the tree:
//   - both boundaries already list `provider.go-limit` (upstream fixed it): exit 78 with the exact
//     files to delete, because the patch must not survive its reason;
//   - only one boundary lists it (partial upstream fix): exit 65 with a review instruction, never a
//     second insertion;
//   - the pinned version or the exact LIMIT_ERROR_TYPES shape moved: exit 65 with a review
//     instruction, never a blind replacement.
import fs from 'node:fs';

const expectedVersion = '2.6.0';
const root = process.argv[2] || process.cwd();

const fail = (code, message) => {
  console.error(message);
  process.exit(code);
};

const packageJson = JSON.parse(fs.readFileSync(`${root}/package.json`, 'utf8'));
if (packageJson.version !== expectedVersion) {
  fail(
    65,
    `openchamber go-limit patch: source version ${packageJson.version} differs from the pinned ${expectedVersion}. ` +
      'Review the new sources and update or remove packages/overlays/fix/openchamber/patch-go-limit.mjs; ' +
      'the patch is not applied to an unverified version.',
  );
}

const policyFile = `${root}/packages/web/server/lib/limit-failover/policy.js`;
const runtimeFile = `${root}/packages/web/server/lib/limit-failover/runtime.js`;

const policyOriginal = fs.readFileSync(policyFile, 'utf8');
const runtimeOriginal = fs.readFileSync(runtimeFile, 'utf8');

const occurrences = (source, needle) => source.split(needle).length - 1;

// The two lines after which the new member belongs. Keeping the whole neighbour pair as the anchor
// makes a reordered or extended set a source change that needs review, not a silent insert.
const policyAnchor = [
  "  'provider.model-budget-limit',",
  "  'provider.rate-limit',",
  ']);',
].join('\n');
const policyReplacement = [
  "  'provider.model-budget-limit',",
  "  'provider.go-limit',",
  "  'provider.rate-limit',",
  ']);',
].join('\n');

// The plugin source is a template literal; this is its exact one-line Set literal.
const runtimeAnchor =
  '"provider.model-budget-limit", "provider.rate-limit"])';
const runtimeReplacement =
  '"provider.model-budget-limit", "provider.go-limit", "provider.rate-limit"])';

const policyCount = occurrences(policyOriginal, 'provider.go-limit');
const runtimeCount = occurrences(runtimeOriginal, 'provider.go-limit');

if (policyCount > 1 || runtimeCount > 1) {
  fail(
    65,
    'openchamber go-limit patch: provider.go-limit appears more than once in a boundary. ' +
      'Review packages/web/server/lib/limit-failover/policy.js and runtime.js; refusing to insert a duplicate.',
  );
}

if (policyCount === 1 && runtimeCount === 1) {
  fail(
    78,
    'openchamber go-limit patch: OpenChamber 2.6.0 already lists provider.go-limit at both ' +
      'limit-failover boundaries (policy.js and the generated runtime plugin). The compatibility patch is ' +
      'obsolete: remove patch-go-limit.mjs and its installPhase registration in ' +
      'packages/overlays/fix/openchamber/default.nix.',
  );
}

if (policyCount !== runtimeCount) {
  fail(
    65,
    `openchamber go-limit patch: partial upstream fix - policy.js ${policyCount === 1 ? 'handles' : 'does not handle'} ` +
      `provider.go-limit, the generated runtime plugin ${runtimeCount === 1 ? 'handles' : 'does not handle'} it. ` +
      'Review the upstream change and update or remove the patch; refusing to double-insert or guess.',
  );
}

for (const [source, anchor, label] of [
  [policyOriginal, policyAnchor, 'policy.js LIMIT_ERROR_TYPES'],
  [runtimeOriginal, runtimeAnchor, 'runtime.js generated plugin source'],
]) {
  const count = occurrences(source, anchor);
  if (count !== 1) {
    fail(
      65,
      `openchamber go-limit patch: source drift in ${label} - expected one exact anchor, found ${count}. ` +
        'Review the pinned upstream sources and update or remove the patch.',
    );
  }
}

fs.writeFileSync(policyFile, policyOriginal.replace(policyAnchor, policyReplacement));
fs.writeFileSync(runtimeFile, runtimeOriginal.replace(runtimeAnchor, runtimeReplacement));
console.log('openchamber go-limit patch: added provider.go-limit to policy.js and the runtime plugin');
