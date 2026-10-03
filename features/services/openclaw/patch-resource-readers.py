"""Apply the same narrowly scoped Nix resource policy to gateway and embedded worker readers.

Consumer fragments are deliberately release-bound. A changed or missing native guard fails the
build, rather than silently delivering a partially patched package after a release update.
"""
from pathlib import Path
import shutil
import sys


def patch(package_root, policy_source):
    root = Path(package_root)
    dist = root / 'dist'
    normal = [p for p in dist.iterdir() if p.suffix in ('.js', '.mjs') and p.is_file()]
    specifications = [
        ('async function readSkillBundleTree(directory, includePath, options)',
         'hardlinks: "reject",', 'hardlinks: resourceHardlinkPolicy(directory),'),
        ('async function readPluginControlUiAssets(rootDir, declaration)',
         'hardlinks: "reject",', 'hardlinks: resourceHardlinkPolicy(rootDir),'),
        ('async function loadPackageIcon(params)',
         'rejectHardlinks: true', 'rejectHardlinks: resourceHardlinkPolicy(params.rootPath) === "reject"'),
        ('function resolvePluginArtifactManifests(rootDir, env = process.env, context = {})',
         'rejectHardlinks: true', 'rejectHardlinks: resourceHardlinkPolicy(artifactRoot, env) === "reject"'),
    ]
    worker = dist / 'worker/worker.mjs'
    worker_specifications = [
        ('async function readSkillBundleTree(Ot,Zt,_n)',
         'hardlinks:`reject`', 'hardlinks:resourceHardlinkPolicy(Ot)'),
        ('async function readPluginControlUiAssets(Ot,Zt)',
         'hardlinks:`reject`', 'hardlinks:resourceHardlinkPolicy(Ot)'),
        ('async function loadPackageIcon(Ot)',
         'rejectHardlinks:!0', 'rejectHardlinks:resourceHardlinkPolicy(Ot.rootPath)===`reject`'),
        ('function resolvePluginArtifactManifests(Ot,Zt=process.env,_n={})',
         'rejectHardlinks:!0', 'rejectHardlinks:resourceHardlinkPolicy(Dn,Zt)===`reject`'),
    ]
    changes = {}

    def replace(file, signature, original, replacement):
        text = changes.get(file, file.read_text())
        if text.count(signature) != 1:
            raise ValueError(f'Expected exactly one native reader signature in {file}: {signature}')
        start = text.index(signature)
        # Guards occur near the reader entry point; never match a different consumer later in a chunk.
        end = min(start + 2600, len(text))
        fragment = text[start:end]
        if fragment.count(original) != 1:
            raise ValueError(f'Expected exactly one unchanged hardlink guard in {file}: {signature}')
        changes[file] = text[:start] + fragment.replace(original, replacement, 1) + text[end:]

    for signature, original, replacement in specifications:
        owners = [p for p in normal if signature in p.read_text()]
        if len(owners) != 1:
            raise ValueError(f'Expected exactly one gateway consumer for {signature}, found {len(owners)}')
        replace(owners[0], signature, original, replacement)
    for specification in worker_specifications:
        replace(worker, *specification)
    policy = Path(policy_source).read_text()
    if policy.count("import fs from 'node:fs';") != 1 or policy.count('export function resourceHardlinkPolicy') != 1:
        raise ValueError('Expected one self-contained filesystem policy for standalone worker embedding')
    embedded_policy = policy.replace("import fs from 'node:fs';", "import nixResourceFs from 'node:fs';")
    embedded_policy = embedded_policy.replace('export function resourceHardlinkPolicy', 'function resourceHardlinkPolicy')
    embedded_policy = embedded_policy.replace('fs.', 'nixResourceFs.')
    # Validate every contract before writing anything, including the separately bundled worker.
    for file, text in changes.items():
        # Device bootstrap ships worker.mjs alone. Embed from the same source, never introduce a
        # package-relative import into that standalone transport artifact.
        header = embedded_policy if file == worker else 'import { resourceHardlinkPolicy } from "./nix-resource-policy.mjs";\n'
        file.write_text(header + '\n' + text)
    shutil.copyfile(policy_source, dist / 'nix-resource-policy.mjs')
    print('Expected four gateway and four embedded-worker resource consumers using one Nix policy: patched')


if __name__ == '__main__':
    patch(*sys.argv[1:])
