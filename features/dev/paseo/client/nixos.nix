# The Paseo desktop client.
#
# It is only a client: it connects to a daemon over the mesh and owns no agent state. Keeping it a
# separate module means a workstation can show every host's agents without running a daemon of its
# own, and a server can run a daemon without pulling an Electron app into its closure.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.dev.paseo.client;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  options.my.features.dev.paseo.client = {
    enable = lib.mkEnableOption "the Paseo desktop client";

    package = lib.mkOption {
      type = lib.types.package;
      # Upstream builds the desktop with `--ignore-scripts`, so `npm run postinstall` never runs and
      # `patches/@gorhom+bottom-sheet+5.2.14.patch` is not applied; the renderer then has no
      # `BottomSheetModalInternalProvider` and any chat crashes with React #130. The upstream issue
      # names this override as the fix (getpaseo/paseo#7673).
      default = inputs.paseo.packages.${system}.desktop.overrideAttrs (previous: {
        preBuild = (previous.preBuild or "") + "\nnpm run postinstall";
      });
      defaultText = lib.literalExpression "inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.desktop";
      description = "Paseo desktop package, with the postinstall patch upstream's Nix build skips.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
