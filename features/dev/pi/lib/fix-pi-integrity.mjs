// features/dev/pi/lib/fix-pi-integrity.mjs
// Upstream lockfiles for several pi plugins omit `integrity` for the nested
// `@earendil-works/pi-*` packages (peer/dev deps of the pi runtime). fetch-npm-deps
// rejects these with "non-git dependencies should have associated integrity".
//
// This injects the missing hashes. Keys are version-scoped (name@version) and
// the script fails loudly when it encounters a version it does not know, so a
// pi-* version bump surfaces as an explicit build error instead of silently
// reusing stale hashes.
import { readFileSync, writeFileSync } from "node:fs";

const integrity = {
  "@earendil-works/pi-agent-core@0.84.0":
    "sha512-L1lw0lwR5LXCzGEeHD9XNEruU2bg0H8clOA8ySdGMHvxutp8GC+yZL6MZp4tqQRnLKP3gHmY7TrWzQ3YnFdJYQ==",
  "@earendil-works/pi-ai@0.84.0":
    "sha512-N9RDk8q0eglGiy+NqTZ3Ev2j+6oFNXSAJa8b0CYhvWB9HGiKZjsoCESXkUvMDLybrn0wXp75sdsoBzEtHxk9kA==",
  "@earendil-works/pi-client@0.84.0":
    "sha512-fHXgw1FdLDh+uw42SvTkJRBfgc3nsrslghvbRFEAxdjfcOxJt7hPsTj4HHNK96wMy1f+zvQYL8Y2znvFoZ8JDA==",
  "@earendil-works/pi-protocol@0.84.0":
    "sha512-Fc28cCYGg5+aRnMzbAD7QAi6Xl//kbETyFroLHCs3Zf4oaXH9L2gzBqVLVAwrKIKeS0uffUrmihocGTECfKW6Q==",
  "@earendil-works/pi-telemetry@0.84.0":
    "sha512-g6hLxEfAUk3zJlDmFWhWHJNcYXYiNGeWuJC9YkcHpkdkj0gxD4uaMNNNU3QsAEJXW9Qcxnl21+U8GfhVsc8C5g==",
  "@earendil-works/pi-tui@0.84.0":
    "sha512-nbs0FeZJ5rWDD6VpKfXXmYbEHnHqb40V9glE2l9f8ftoWpsP8nw0WcXK8jOjfRsDPnT9dJHy3dItOHdn/AFGjA==",
  "@earendil-works/pi-agent-core@0.84.1":
    "sha512-evyzXYWCLQGmcaBYHlmSku02r8qoN4SGI60GZABo6iV+H+nqX+P9ud8fEZ4GmRq9mUSREvvfX+w9dA9ThF9C6w==",
  "@earendil-works/pi-ai@0.84.1":
    "sha512-wMsAdJMxuNri08vLqTyYVI201DQQezGhPSTkzYsHdw5dYX3rCNwEmSvpaAwhi7ELKI/2tE/CEgSWg/6iRxSgdQ==",
  "@earendil-works/pi-client@0.84.1":
    "sha512-/V5hGHE4Zq+jG0GtwIB9PyBUOGd6gBLZ7lkQYFKchKnxYHeH3rmWC5xw4kpnZKKBuBuFTdLVbU9vEjlAGMMb2A==",
  "@earendil-works/pi-protocol@0.84.1":
    "sha512-Ox1pciyeSPGEEUcxvR0/dJcrY7C6hrEGA8y71rOsvSIUlXN1Cbp/be/eoL71OGDBk5O97TeQPfWN6Ju/2Ehjww==",
  "@earendil-works/pi-telemetry@0.84.1":
    "sha512-180/xGJtsq7IoR3p9EKWjRd0e9M4DkxInhlo9xyD7prDC7Qrhqq+nhvwrW0lFjPfXcEI2FSHmGCSyvSJE9GsaQ==",
  "@earendil-works/pi-tui@0.84.1":
    "sha512-udeXFbgEhJ6JiB0uguwNVNkDy2FENfmtQwPcY+/iJ8GWeq18wkal1tKqa5YyeH0IqtX1vG0cGh8zfSYzyzVuLA==",
};

const file = process.argv[2];
if (!file) {
  console.error("usage: node fix-pi-integrity.mjs <package-lock.json>");
  process.exit(1);
}

const lock = JSON.parse(readFileSync(file, "utf8"));
let fixed = 0;
for (const [key, entry] of Object.entries(lock.packages ?? {})) {
  const name = key.match(/node_modules\/(@earendil-works\/[^/]+)$/)?.[1];
  if (!name || entry.integrity || !entry.resolved) continue;

  const version = entry.resolved.match(/([0-9]+\.[0-9]+\.[0-9]+)\.tgz$/)?.[1];
  if (!version) continue;

  const lookup = `${name}@${version}`;
  if (!integrity[lookup]) {
    console.error(`fix-pi-integrity: no integrity recorded for ${lookup} — update the integrity map.`);
    process.exit(1);
  }
  entry.integrity = integrity[lookup];
  fixed += 1;
}

if (fixed > 0) {
  writeFileSync(file, JSON.stringify(lock, null, 2) + "\n");
  console.error(`fix-pi-integrity: injected integrity for ${fixed} package(s) in ${file}`);
}
