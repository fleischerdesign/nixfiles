// Make OpenChamber's Linux autostart entry name the fleet launcher instead of Electron's execPath.
//
// Upstream writes `Exec=<process.execPath> --background` whenever the autostart file exists and
// reconciles it again on every start. The packaged binary therefore replaces the launcher wrapper
// that exports the provisioning hook and the desktop user-data dir, and the next login starts an
// unprovisioned instance. The launcher exports OPENCHAMBER_AUTOSTART_EXEC with its own store path;
// this patch makes the resolver prefer that absolute path, so upstream's toggle and its startup
// reconcile write the same launcher the desktop entry already names.
//
// Fails closed when the pinned version or the exact function shape moves.
import fs from 'node:fs';

const expectedVersion = '2.6.0';
const versionFile = 'packages/electron/package.json';
const sourceFile = 'packages/electron/linux-autostart.mjs';

const version = JSON.parse(fs.readFileSync(versionFile, 'utf8')).version;
if (version !== expectedVersion) {
  console.error(
    `openchamber autostart patch: expected ${expectedVersion}, found ${version}; re-verify the resolver before bumping`,
  );
  process.exit(1);
}

let source = fs.readFileSync(sourceFile, 'utf8');
if (source.includes('OPENCHAMBER_AUTOSTART_EXEC')) {
  console.error('openchamber autostart patch: source already carries the override');
  process.exit(1);
}

const original = `export const resolveLinuxLaunchExecutable = ({
  env = process.env,
  execPath = process.execPath,
} = {}) => {`;

const patched = `export const resolveLinuxLaunchExecutable = ({
  env = process.env,
  execPath = process.execPath,
} = {}) => {
  // The declared launcher is the only path that carries the provisioning environment.
  const declaredLauncher = typeof env.OPENCHAMBER_AUTOSTART_EXEC === 'string'
    ? env.OPENCHAMBER_AUTOSTART_EXEC.trim()
    : '';
  if (declaredLauncher && path.isAbsolute(declaredLauncher)) {
    return declaredLauncher;
  }`;

const count = source.split(original).length - 1;
if (count !== 1) {
  console.error(
    `openchamber autostart patch: expected one resolveLinuxLaunchExecutable anchor, found ${count}`,
  );
  process.exit(1);
}

source = source.replace(original, patched);
fs.writeFileSync(sourceFile, source);
