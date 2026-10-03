// Exercise the actual packaged resource readers, with real hardlinks and hostile mutable fixtures.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [gateway, linkedFixture] = process.argv.slice(2);
const packageRoot = fs.realpathSync(path.join(gateway, 'lib/openclaw'));
const dist = path.join(packageRoot, 'dist');
const { resourceHardlinkPolicy } = await import(pathToFileURL(path.join(dist, 'nix-resource-policy.mjs')));
async function reader(signature, exported) {
  const owners = fs.readdirSync(dist).filter(name => /\.m?js$/.test(name))
    .map(name => path.join(dist, name)).filter(file => fs.readFileSync(file, 'utf8').includes(signature));
  assert.equal(owners.length, 1, `Expected one packaged reader: ${signature}`);
  return (await import(pathToFileURL(owners[0])))[exported];
}
const readSkills = await reader('async function readSkillBundleTree(', 'o');
const readUi = await reader('async function readPluginControlUiAssets(', 'r');
const inspectArtifact = await reader('function resolvePluginArtifactManifests(', 't');
const prepareDelivery = await reader('async function prepareSkillResourceDelivery(', 'n');
const materializeDelivery = await reader('async function materializeSkillResources(', 't');
assert.equal(typeof readSkills, 'function');
assert.equal(typeof readUi, 'function');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'openclaw-resources-'));
const envBefore = process.env.OPENCLAW_NIX_MODE;
try {
  process.env.OPENCLAW_NIX_MODE = '1';
  const standalone = path.join(temporary, 'worker.mjs');
  fs.copyFileSync(path.join(dist, 'worker/worker.mjs'), standalone);
  execFileSync(process.execPath, [standalone, '--internal-worker-prewarm'], {
    timeout: 60000, stdio: ['ignore', 'pipe', 'inherit'],
  });
  assert(fs.statSync(path.join(linkedFixture, 'SKILL.md')).nlink > 1, 'Expected genuine immutable hardlinks');
  assert.equal(resourceHardlinkPolicy(linkedFixture), 'allow');
  assert.equal(resourceHardlinkPolicy(linkedFixture, {}), 'reject', 'Expected explicit Nix opt-in');
  assert.equal(resourceHardlinkPolicy('/nix/store'), 'reject', 'Expected an output root, not the entire store');
  await readSkills(linkedFixture);
  process.env.OPENCLAW_NIX_MODE = '0';
  assert.equal(resourceHardlinkPolicy(linkedFixture), 'reject');
  await assert.rejects(readSkills(linkedFixture), /hardlink/i);
  process.env.OPENCLAW_NIX_MODE = '1';

  let skills = 0;
  const resolvedSkills = [];
  const skillRoots = [path.join(packageRoot, 'skills')];
  const extensions = path.join(dist, 'extensions');
  for (const plugin of fs.readdirSync(extensions)) {
    const root = path.join(extensions, plugin, 'skills');
    if (fs.existsSync(root)) skillRoots.push(root);
  }
  for (const root of skillRoots) {
    for (const name of fs.readdirSync(root)) {
      const skill = path.join(root, name);
      if (!fs.existsSync(path.join(skill, 'SKILL.md'))) continue;
      await readSkills(skill, undefined, { symlinks: 'follow-within-root' });
      resolvedSkills.push({ name, baseDir: skill, filePath: path.join(skill, 'SKILL.md'),
        description: 'Synthetic resource-consumer qualification' });
      skills++;
    }
  }
  assert(skills > 8, 'Expected coverage of bundled and plugin-provided skills');
  const delivery = await prepareDelivery({ resolvedSkills, skills: resolvedSkills }, () => {});
  assert.equal(delivery.skills.length, skills, 'Expected native worker resource-delivery coverage');
  const materialized = await materializeDelivery(delivery, () => {});
  try {
    assert.equal(materialized.snapshot.resolvedSkills.length, skills);
    for (const skill of materialized.snapshot.resolvedSkills) {
      assert.equal(fs.statSync(skill.filePath).nlink, 1, 'Expected native single-link worker inputs');
    }
  } finally {
    await materialized.cleanup();
  }
  let uiBuilds = 0;
  for (const plugin of fs.readdirSync(extensions)) {
    const root = path.join(extensions, plugin);
    const manifest = path.join(root, 'openclaw.plugin.json');
    if (!fs.existsSync(manifest)) continue;
    const declaration = JSON.parse(fs.readFileSync(manifest, 'utf8')).controlUi;
    if (!declaration) continue;
    const result = await readUi(root, declaration);
    assert(result.assets.size > 0, 'Expected a complete native UI asset build');
    uiBuilds++;
  }
  assert(uiBuilds > 0, 'Expected native plugin UI resource coverage');
  assert.equal(typeof inspectArtifact, 'function');
  assert(inspectArtifact(path.join(extensions, 'browser')).manifest,
    'Expected native immutable plugin artifact inspection');

  const mutable = path.join(temporary, 'mutable');
  fs.mkdirSync(mutable);
  fs.writeFileSync(path.join(mutable, 'SKILL.md'), 'synthetic skill');
  await readSkills(mutable);
  fs.linkSync(path.join(mutable, 'SKILL.md'), path.join(temporary, 'outside-hardlink'));
  assert.equal(resourceHardlinkPolicy(mutable), 'reject');
  await assert.rejects(readSkills(mutable), /hardlink/i);
  fs.writeFileSync(path.join(mutable, 'index.js'), 'export const synthetic = true;');
  fs.linkSync(path.join(mutable, 'index.js'), path.join(temporary, 'outside-ui-hardlink'));
  await assert.rejects(readUi(mutable, { entry: 'index.js' }), /hardlink/i);
  fs.writeFileSync(path.join(mutable, 'package.json'), '{}');
  fs.linkSync(path.join(mutable, 'package.json'), path.join(temporary, 'outside-manifest-hardlink'));
  assert.throws(() => inspectArtifact(mutable), /manifest/i);
  await assert.rejects(readSkills(path.join(temporary, 'missing')));

  const symlinked = path.join(temporary, 'store-alias');
  fs.symlinkSync(linkedFixture, symlinked);
  assert.equal(resourceHardlinkPolicy(symlinked), 'allow', 'Expected canonical store resolution');
  await readSkills(symlinked);
  const shaped = path.join(temporary, 'nix/store', 'a'.repeat(32) + '-fake');
  fs.mkdirSync(shaped, { recursive: true });
  assert.equal(resourceHardlinkPolicy(shaped), 'reject', 'Expected lexical store impersonation to fail');

  const escape = path.join(temporary, 'escape');
  fs.mkdirSync(escape);
  fs.symlinkSync(path.join(temporary, 'outside-hardlink'), path.join(escape, 'SKILL.md'));
  await assert.rejects(readSkills(escape, undefined, { symlinks: 'follow-within-root' }));
  await assert.rejects(readUi(mutable, { entry: '../outside.js' }));
  fs.writeFileSync(path.join(mutable, 'oversized.js'), Buffer.alloc(4194305));
  fs.unlinkSync(path.join(mutable, 'index.js'));
  await assert.rejects(readUi(mutable, { entry: 'oversized.js' }));
  console.log(`Expected ${skills} official skill bundles and ${uiBuilds} native UI builds accepted; mutable hardlinks, escapes, missing roots and oversized assets rejected: verified`);
} finally {
  if (envBefore === undefined) delete process.env.OPENCLAW_NIX_MODE;
  else process.env.OPENCLAW_NIX_MODE = envBefore;
  fs.rmSync(temporary, { recursive: true, force: true });
}
