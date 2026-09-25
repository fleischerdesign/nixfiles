# features/dev/pi/plugins/pi-lens/package.nix
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
    tarballUrl = "https://registry.npmjs.org/${manifest.name}/-/${pnameOf manifest.name}-${manifest.version}.tgz";
    lockfile = ./package-lock.json;
  };

  dontNpmBuild = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
    "--ignore-scripts"
  ];

  postPatch = ''
    node -e '
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      delete pkg.scripts.prepack;
      delete pkg.scripts.postpack;
      delete pkg.scripts.prepare;
      fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
    '
  '';

  meta = with lib; {
    description = "Real-time code feedback for pi — LSP, linters, formatters, type-checking, structural analysis";
    homepage = "https://github.com/apmantza/pi-lens";
    license = licenses.mit;
  };
}
