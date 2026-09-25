# features/dev/pi/plugins/pi-goal-x/package.nix
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
  ];

  # pi-goal-x has only peerDependencies at runtime; ensure node_modules exists
  # so buildNpmPackage's postInstall checks pass cleanly.
  preInstall = ''
    mkdir -p node_modules
  '';

  postInstall = ''
    mkdir -p "$out/lib/node_modules/${manifest.name}/node_modules"
  '';

  meta = with lib; {
    description = "Conversational goal planning, ordered Sisyphus flows, and completion auditor for Pi";
    homepage = "https://github.com/tmonk/pi-goal-x";
    license = licenses.mit;
  };
}
