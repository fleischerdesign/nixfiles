// Resolve missing npm integrity metadata during updates, then vendor the lockfile.
// Builds consume those exact bytes and never contact the registry for metadata.
import { readFileSync, writeFileSync } from "node:fs";

const file = process.argv[2];
if (!file) throw new Error("usage: node fix-npm-integrity.mjs <package-lock.json>");
const lock = JSON.parse(readFileSync(file, "utf8"));
const requests = new Map();
for (const entry of Object.values(lock.packages ?? {})) {
  if (entry.integrity || !entry.resolved || entry.link) continue;
  if (entry.resolved.startsWith("git")) continue;
  const url = new URL(entry.resolved);
  if (url.origin !== "https://registry.npmjs.org") {
    throw new Error(`Missing integrity for unsupported registry: ${url.origin}`);
  }
  const [name, archive] = decodeURIComponent(url.pathname).slice(1).split("/-/");
  const basename = name.split("/").at(-1);
  if (!archive?.startsWith(`${basename}-`) || !archive.endsWith(".tgz")) {
    throw new Error(`Cannot identify npm tarball: ${entry.resolved}`);
  }
  const version = archive.slice(basename.length + 1, -4);
  const key = `${name}@${version}`;
  if (!requests.has(key)) {
    const response = await fetch(`https://registry.npmjs.org/${name}/${version}`);
    if (!response.ok) throw new Error(`${key}: registry returned ${response.status}`);
    requests.set(key, await response.json());
  }
  const metadata = requests.get(key);
  if (metadata.dist?.tarball !== entry.resolved || !metadata.dist.integrity) {
    throw new Error(`${key}: registry metadata does not match the locked tarball`);
  }
  entry.integrity = metadata.dist.integrity;
}
writeFileSync(file, JSON.stringify(lock, null, 2) + "\n");
