# features/dev/pi/plugins/pi-mcp-adapter/package.nix
{
  buildNpmPackage,
  lib,
  mkSrc,
  pnameOf,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
buildNpmPackage {
  pname = pnameOf manifest.name;
  inherit (manifest) version npmDepsHash;

  src = mkSrc {
    inherit manifest;
    lockfile = if builtins.pathExists ./package-lock.json then ./package-lock.json else null;
  };

  # Pi loads index.ts directly, but newer releases also export compiled public modules.
  # Older releases have no public build script; their exports still get checked below.
  npmBuildScript = "build:public";
  npmBuildFlags = [ "--if-present" ];
  npmFlags = [ "--legacy-peer-deps" ];
  npmRebuildFlags = [ "--ignore-scripts" ];
  makeCacheWritable = true;
  # Build once, before npmInstallHook prunes the development dependencies.
  npmPackFlags = [ "--ignore-scripts" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node --input-type=module - "$out/lib/node_modules/${manifest.name}" <<'JS'
    import assert from 'node:assert/strict';
    import fs from 'node:fs';
    import path from 'node:path';
    import { pathToFileURL } from 'node:url';
    const root = process.argv[2];
    const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
    async function check(target) {
      if (typeof target !== 'string') {
        for (const value of Object.values(target)) await check(value);
        return;
      }
      const file = path.join(root, target);
      assert.ok(fs.existsSync(file), `Missing installed export: ''${target}`);
      if (target.endsWith('.js')) await import(pathToFileURL(file));
    }
    await check(pkg.exports);
    for (const entry of pkg.pi.extensions) await check(entry);
    JS
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "MCP (Model Context Protocol) adapter extension for pi";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = licenses.mit;
  };
}
