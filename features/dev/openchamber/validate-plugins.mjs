import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [app, root] = process.argv.slice(2);
const { inspectGuestPackage } = await import(pathToFileURL(path.join(app, 'packages/web/server/lib/guests/catalog.js')));
const { version } = JSON.parse(await fs.readFile(path.join(app, 'package.json'), 'utf8'));
const registry = JSON.parse(await fs.readFile(path.join(root, 'registry.json'), 'utf8'));
for (const entry of registry.extensions) {
  const result = await inspectGuestPackage(path.join(root, entry.directory), { openchamberVersion: version });
  if (!result.ok) throw new Error(`OpenChamber extension ${entry.id}: ${result.code}: ${result.reason ?? ''}`);
  if (result.guest.id !== entry.id) throw new Error(`OpenChamber extension ID mismatch: ${entry.id}`);
}
