#!/usr/bin/env node
// Link every workspace package into the tree root's node_modules.
//
// The Cordis loader imports workspace packages by bare name (e.g.
// `@deepseek-ai/dsh-client-locale`) from vendor/loader; Node resolves those
// through the ancestor node_modules chain, which ends at the tree root. The
// published npm layout is flat (every dependency in one node_modules), while
// a pnpm workspace links packages per-dependent — so the deployed workspace
// tree mirrors the flat layout by symlinking every workspace package into
// the root node_modules. Existing links are never overwritten.
import { existsSync, mkdirSync, readFileSync, readdirSync, symlinkSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'

const root = resolve(process.argv[2])

/** Read subdirectory names, tolerating absent directories. */
function readDirs(path) {
  if (!existsSync(path)) return []
  return readdirSync(path, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
}

/** Relative workspace package directories (skip non-workspace trees like website/). */
const workspaceDirs = [
  ...readDirs(join(root, 'vendor')).map((d) => join('vendor', d)),
  ...readDirs(join(root, 'packages')).flatMap((a) =>
    readDirs(join(root, 'packages', a)).map((b) => join('packages', a, b)),
  ),
  ...readDirs(join(root, 'apps')).map((d) => join('apps', d)),
  ...readDirs(join(root, 'native', 'landlock-run', 'packages')).map((d) =>
    join('native', 'landlock-run', 'packages', d),
  ),
]

const nodeModules = join(root, 'node_modules')
let linked = 0
let skipped = 0
for (const rel of workspaceDirs) {
  const manifestPath = join(root, rel, 'package.json')
  if (!existsSync(manifestPath)) continue
  let name
  try {
    name = JSON.parse(readFileSync(manifestPath, 'utf8')).name
  } catch {
    continue
  }
  if (typeof name !== 'string' || name.length === 0) continue

  const linkPath = join(nodeModules, name)
  if (existsSync(linkPath)) {
    skipped += 1
    continue
  }
  mkdirSync(dirname(linkPath), { recursive: true })
  symlinkSync(relative(dirname(linkPath), join(root, rel)), linkPath)
  linked += 1
}
console.log(`workspace-links: ${linked} linked, ${skipped} already present`)
