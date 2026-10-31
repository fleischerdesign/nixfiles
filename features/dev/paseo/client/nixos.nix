# The Paseo desktop client.
#
# It is only a client: it connects to a daemon over the mesh and owns no agent state. Keeping it a
# separate module means a workstation can show every host's agents without running a daemon of its
# own, and a server can run a daemon without pulling an Electron app into its closure.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.dev.paseo.client;
in
{
  options.my.features.dev.paseo.client = {
    enable = lib.mkEnableOption "the Paseo desktop client";

    package = lib.mkOption {
      type = lib.types.package;
      # The overlay in packages/overlays/fix/paseo-desktop owns the build step upstream's Nix
      # desktop package skips; this module only decides where the app is installed.
      default = pkgs.paseo-desktop;
      defaultText = lib.literalExpression "pkgs.paseo-desktop";
      description = "Paseo desktop package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
