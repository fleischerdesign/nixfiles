# features/dev/dsh/plugins/dsh-mesh/package.nix
# dsh-mesh: Distributed P2P mesh fabric over Tailscale.
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
