{
  lib,
  pkgs,
  inputs,
}:
let
  release = import ./release.nix;
  sourceInfo = import "${inputs.openclaw}/nix/sources/openclaw-source.nix";
  packages = inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system};
  # Keep the official locked package graph and installation recipe. The local adaptation extends
  # its immutable-store hardlink handling to resource consumers, not executable/plugin discovery.
  gateway = packages.openclaw-gateway.overrideAttrs (previous: {
    installPhase = ''
      ${previous.installPhase}
      ${pkgs.python3}/bin/python3 ${./patch-resource-readers.py} \
        "$out/lib/openclaw" ${./nix-resource-policy.mjs}
      "$NODE_BIN" --check "$out/lib/openclaw/dist/worker/worker.mjs"
    '';
  });
  runtimePlugins = lib.mapAttrs' (
    name: package: lib.nameValuePair (lib.removePrefix "openclaw-runtime-plugin-" name) package
  ) (lib.filterAttrs (name: _: lib.hasPrefix "openclaw-runtime-plugin-" name) packages);
in
assert lib.assertMsg (
  release.releaseVersion == sourceInfo.releaseVersion && release.releaseRev == sourceInfo.rev
) "OpenClaw release.nix must match the pinned nix-openclaw source release";
{
  inherit release runtimePlugins;
  inherit gateway;
  package = packages.openclaw.override { openclaw-gateway = gateway; };
}
