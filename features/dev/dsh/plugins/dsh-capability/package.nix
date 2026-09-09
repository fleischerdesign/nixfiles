# features/dev/dsh/plugins/dsh-capability/package.nix
# dsh-capability: granular capability-based authorization primitive for the mesh.
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
