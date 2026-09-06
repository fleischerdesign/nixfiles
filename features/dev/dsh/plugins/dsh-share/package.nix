# features/dev/dsh/plugins/dsh-share/package.nix
# dsh-share: Capability-based session sharing, targeted ACLs, zero-leakage redaction, and instant revocation.
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
