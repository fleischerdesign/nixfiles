# features/dev/dsh/plugins/dsh-ingress/package.nix
# dsh-ingress: CloudEvents v1.0 reactive event ingress gateway.
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
