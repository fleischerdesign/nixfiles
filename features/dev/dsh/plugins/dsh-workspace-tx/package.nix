# features/dev/dsh/plugins/dsh-workspace-tx/package.nix
# dsh-workspace-tx: Multi-Repository Two-Phase Commit (MR-2PC) workspace transaction engine.
{
  callPackage,
  dsh,
  ...
}:

let
  buildDshPlugin = callPackage ../../lib/build-plugin.nix { inherit dsh; };
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
buildDshPlugin {
  pname = manifest.name;
  inherit (manifest) version;
  src = ./.;
  description = manifest.description;
  hasClient = false;
}
