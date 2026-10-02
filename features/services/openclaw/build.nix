# Resolves the OpenClaw release and the external plugin catalogue against the pinned nix-openclaw
# packaging, and produces a gateway that carries the catalogue plugins as bundled extensions.
#
#   release.nix        - the version, tag commit and runtime-plugin version this fleet runs.
#   plugins.nix        - the loader; the plugins themselves live in plugins/<id>/plugin.nix.
#   build.nix          - resolves both against `inputs.openclaw` and asserts they agree.
#
# Why the plugins are bundled rather than load-path entries
# ---------------------------------------------------------
# OpenClaw resolves several runtime SDK surfaces (`openBlobStore`, `openKeyedStore`, channel ingress
# queues) only for a plugin whose recorded origin is `bundled` or whose recorded install is
# `trusted-official` (`dist/loader-runtime-load-*.mjs`: `record.origin !== "bundled" &&
# record.trustedOfficialInstall !== true`). A root named through `plugins.load.paths` is neither: its
# trust reason is `record-missing`. nix-openclaw's own supported `runtimePlugins` path renders the
# same `plugins.load.paths`, so this is a property of Nix-declared plugins, not of a particular
# wiring. A plugin that touches a trust-gated surface therefore fails at registration from a load
# path - `diffs` calls `openBlobStore` and does exactly that.
#
# The gateway itself solves this for its bundled ACPX runtime by copying the plugin *physically* into
# `dist/extensions/<id>`, because discovery requires containment rather than a symlink. This file
# applies the same, proven mechanism to every catalogue plugin: the gateway closure carries them, and
# each is `bundled` and therefore trusted. The plugins are built without the OpenClaw peer link
# (`linkOpenClawPeer = false`) so the gateway does not depend on itself; the host SDK resolves from
# the containing gateway's own `node_modules` at runtime.
{
  lib,
  pkgs,
  inputs,
}:
let
  release = import ./release.nix;
  # A flat attribute set keyed by plugin identifier; the loader derives the identifier from the
  # plugin's folder name and validates every record.
  all = import ./plugins.nix { inherit lib; };
  sourceInfo = import "${inputs.openclaw}/nix/sources/openclaw-source.nix";
  system = pkgs.stdenv.hostPlatform.system;

  packages = inputs.openclaw.packages.${system};

  # nix-openclaw's generated index maps every plugin identifier to its lock, whatever the lock's file
  # name happens to be (`amazon-bedrock` lives in `amazonBedrock.nix`). Resolving through the index
  # removes any assumption that the file name equals the identifier.
  runtimePluginLocks = import "${inputs.openclaw}/nix/generated/openclaw-runtime-plugins";
  lock =
    id: runtimePluginLocks.${id} or (throw "nix-openclaw has no generated lock for plugin ${id}");

  # Build the plugins from nix-openclaw's own nixpkgs, the same toolchain that built the gateway, so
  # the closure does not mix two nixpkgs instances. `linkOpenClawPeer = false` because a bundled
  # plugin must live inside the gateway and cannot depend on it; the host SDK resolves from the
  # containing gateway's own `node_modules` at runtime. This is the call nix-openclaw uses for its own
  # bundled ACPX runtime.
  openclawPkgs = inputs.openclaw.inputs.nixpkgs.legacyPackages.${system};
  buildBundled = openclawPkgs.callPackage "${inputs.openclaw}/nix/lib/openclaw-runtime-plugin.nix" {
    linkOpenClawPeer = false;
  };
  bundledPlugin = id: buildBundled (lock id);

  # The catalogue resolved to packaged plugin roots, keyed by identifier.
  bundled = lib.mapAttrs (id: _: bundledPlugin id) all;
  pluginVersion = id: (bundled.${id}).openclawRuntimePlugin.version;
  # The lock's own id must equal the folder name; otherwise the wrong package would be bundled under
  # this identifier.
  lockIdMatches = id: (lock id).id == id;

  # Copy each bundled plugin into the gateway's own extension roots. The manifest lives in
  # `extensions/<id>/` for discovery and the code in `dist/extensions/<id>/`, which is the layout the
  # gateway's own runtime-staging script produces for its bundled extensions.
  stageExtensions = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (id: plugin: ''
      root="$out/lib/node_modules/openclaw"
      mkdir -p "$root/dist/extensions/${id}" "$root/extensions/${id}"
      cp -R ${plugin}/. "$root/dist/extensions/${id}/"
      cp "$root/dist/extensions/${id}/openclaw.plugin.json" "$root/extensions/${id}/openclaw.plugin.json"
    '') bundled
  );

  baseGateway = packages.openclaw-gateway;

  # The gateway closure carries the catalogue. `installPhase` is a path to an executable script, so
  # the appended shell commands must start on a new line.
  gateway = baseGateway.overrideAttrs (old: {
    installPhase = (old.installPhase or "") + "\n\n" + stageExtensions;
  });

  # The batteries-included bundle wraps the gateway binary; it must wrap the gateway that carries the
  # catalogue, not the base one.
  package = packages.openclaw.override { openclaw-gateway = gateway; };
in
assert lib.assertMsg (release.releaseVersion == sourceInfo.releaseVersion) (
  "release.nix declares OpenClaw ${release.releaseVersion}, but the pinned nix-openclaw packages "
  + "${sourceInfo.releaseVersion}; update the flake input in the same change"
);
assert lib.assertMsg (release.releaseRev == sourceInfo.rev) (
  "release.nix declares tag commit ${release.releaseRev}, but the pinned nix-openclaw packages "
  + "${sourceInfo.rev}; update the flake input in the same change"
);
assert lib.assertMsg (lib.all (id: pluginVersion id == release.runtimePluginVersion) (
  lib.attrNames all
)) "The nix-openclaw plugin packages do not carry the runtime plugin version release.nix declares";
assert lib.assertMsg (lib.all lockIdMatches (
  lib.attrNames all
)) "A plugin folder name does not match the id of the nix-openclaw lock it resolves to";
{
  inherit
    release
    all
    bundled
    gateway
    package
    ;
}
