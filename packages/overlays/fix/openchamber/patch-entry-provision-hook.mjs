// Insert the fleet provisioning hook into OpenChamber's Electron entry module.
//
// The hook has to run before `app.requestSingleInstanceLock()`: a relaunch starts the binary directly
// and inherits only the environment, so the hook inside the entry module is the authoritative point.
// This patch fails closed when the pinned version or the exact insertion point changes.
import fs from 'node:fs';

const expectedVersion = '2.6.0';
const versionFile = 'packages/electron/package.json';
const entryFile = 'packages/electron/entry.mjs';

const version = JSON.parse(fs.readFileSync(versionFile, 'utf8')).version;
if (version !== expectedVersion) {
  console.error(
    `openchamber provision hook: expected ${expectedVersion}, found ${version}; re-verify the insertion point before bumping`,
  );
  process.exit(1);
}

let source = fs.readFileSync(entryFile, 'utf8');
if (source.includes('OPENCHAMBER_DESKTOP_PROVISION')) {
  if (source.includes('__openchamberProvisionHook')) {
    console.error('openchamber provision hook: entry already patched');
    process.exit(1);
  }
}

const electronImport = "import { app, protocol } from 'electron';";
const lockLine = 'if (!app.requestSingleInstanceLock()) {';
for (const [needle, label] of [
  [electronImport, 'electron import'],
  [lockLine, 'single-instance lock'],
]) {
  const count = source.split(needle).length - 1;
  if (count !== 1) {
    console.error(`openchamber provision hook: expected one ${label}, found ${count}`);
    process.exit(1);
  }
}

source = source.replace(
  electronImport,
  `${electronImport}\nimport { spawnSync as __openchamberSpawnSync } from 'node:child_process';`,
);

const hook = `// Fleet provisioning hook: runs before the single-instance lock, so it also runs after
// app.relaunch(), which starts this binary directly and inherits only the environment.
const __openchamberProvisionHook = String(process.env.OPENCHAMBER_DESKTOP_PROVISION || '').trim();
if (__openchamberProvisionHook) {
  const __openchamberProvision = __openchamberSpawnSync(__openchamberProvisionHook, [], {
    stdio: 'inherit',
    timeout: 60_000,
    env: process.env,
  });
  // 3/4/5: a remote instance is configured but unreachable, denied or missing its mint command.
  // The local in-process server is the substrate, and the app falls back to it when the probe
  // fails, so these must not keep the window shut. 75: another instance owns the profile.
  if (
    __openchamberProvision.error ||
    ![0, 3, 4, 5, 75].includes(__openchamberProvision.status)
  ) {
    process.exit(__openchamberProvision.status || 1);
  }
}
`;

source = source.replace(lockLine, `${hook}${lockLine}`);
fs.writeFileSync(entryFile, source);
