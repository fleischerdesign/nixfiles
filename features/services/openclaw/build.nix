{
  lib,
  pkgs,
  inputs,
}:
let
  release = import ./release.nix;
  sourceInfo = import "${inputs.openclaw}/nix/sources/openclaw-source.nix";
  packages = inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system};
  runtimePlugins = lib.mapAttrs' (
    name: package: lib.nameValuePair (lib.removePrefix "openclaw-runtime-plugin-" name) package
  ) (lib.filterAttrs (name: _: lib.hasPrefix "openclaw-runtime-plugin-" name) packages);
in
assert lib.assertMsg (
  release.releaseVersion == sourceInfo.releaseVersion && release.releaseRev == sourceInfo.rev
) "OpenClaw release.nix must match the pinned nix-openclaw source release";
{
  inherit release runtimePlugins;
  gateway = packages.openclaw-gateway;
  package = packages.openclaw;
}
