# features/dev/dsh/plugins/dsh-auth/package.nix
# dsh-auth: Unified identity and authentication gateway + Tenant HUD Web UI.
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
  hasClient = true;
}
