import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

// This marker records ownership in the command itself, without a second state file.
const marker = "!# Managed by Nix: Pi provider API key\n";
const [packageRoot, specPath, authPath] = process.argv.slice(2);
const require = createRequire(path.join(packageRoot, "package.json"));
const lockfile = require("proper-lockfile");
const quote = (s) => "'" + s.replaceAll("'", "'\\''") + "'";
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

function readObject(file) {
  // Do not include file contents (credentials) in parse errors.
  let value;
  try {
    value = JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
  } catch {
    throw new Error(`Cannot read valid JSON from ${file}; leaving auth unchanged`);
  }
  if (!object(value)) throw new Error(`Expected an object in ${file}`);
  return value;
}

function validateCredentials(data) {
  for (const value of Object.values(data)) {
    if (!object(value)) throw new Error("Invalid credential entry; leaving auth unchanged");
    if (value.type === "api_key" &&
        (value.key === undefined || typeof value.key === "string") &&
        (value.env === undefined || (object(value.env) &&
          Object.values(value.env).every((v) => typeof v === "string")))) continue;
    if (value.type === "oauth" && typeof value.access === "string" &&
        typeof value.refresh === "string" && Number.isFinite(value.expires)) continue;
    throw new Error("Unsupported credential entry; leaving auth unchanged");
  }
}

async function main() {
  const spec = readObject(specPath);
  if (!Array.isArray(spec.providers) || !spec.providers.every((p) => typeof p === "string")) {
    throw new Error("Invalid provider inventory");
  }
  // Verify the replacement's secret source before touching the consumer's auth file.
  const source = readObject(spec.source);
  for (const provider of spec.providers) {
    if (source[provider]?.type !== "api_key" || typeof source[provider].key !== "string" ||
        !source[provider].key.trim()) throw new Error("Missing or empty declared API key");
  }
  fs.mkdirSync(path.dirname(authPath), { recursive: true, mode: 0o700 });
  const release = await lockfile.lock(authPath, {
    realpath: false,
    stale: 30_000,
    retries: { retries: 150, minTimeout: 100, maxTimeout: 200 },
  });
  let temporary;
  try {
    let stat;
    try { stat = fs.lstatSync(authPath); } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    const legacy = stat?.isSymbolicLink() ?? false;
    if (legacy && fs.realpathSync(authPath) !== fs.realpathSync(spec.source)) {
      throw new Error("Refusing to replace an unknown auth symlink");
    }
    if (stat && !legacy && !stat.isFile()) throw new Error("Auth path is not a regular file");
    const current = stat ? readObject(authPath) : {};
    validateCredentials(current);
    const next = Object.fromEntries(Object.entries(current).filter(([, value]) =>
      !(value.type === "api_key" && (legacy || value.key?.startsWith(marker)))));
    for (const provider of spec.providers) {
      // JSON quotes the provider ID; shell quoting keeps both it and the source path literal.
      const filter = `.[${JSON.stringify(provider)}].key | select(type == "string" and length > 0)`;
      Object.defineProperty(next, provider, {
        enumerable: true, configurable: true, writable: true,
        value: { type: "api_key", key: `${marker}exec ${quote(spec.jq)} -er ${quote(filter)} ${quote(spec.source)}` },
      });
    }
    validateCredentials(next);
    const content = JSON.stringify(next, null, 2) + "\n";
    if (!legacy && stat && fs.readFileSync(authPath, "utf8") === content) {
      fs.chmodSync(authPath, 0o600);
      return;
    }
    temporary = fs.mkdtempSync(path.join(path.dirname(authPath), ".auth-reconcile-"));
    const replacement = path.join(temporary, "auth.json");
    fs.writeFileSync(replacement, content, { mode: 0o600 });
    // Read back the complete replacement before removing the original directory entry.
    if (fs.readFileSync(replacement, "utf8") !== content) throw new Error("Auth read-back failed");
    fs.renameSync(replacement, authPath);
  } finally {
    if (temporary) fs.rmSync(temporary, { recursive: true });
    await release();
  }
}

main().catch((error) => {
  console.error(`pi-auth: ${error.message}`);
  process.exitCode = 1;
});
