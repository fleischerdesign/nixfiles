# features/desktop/quickshell/default.nix
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.my.features.desktop.quickshell;
in
{
  options.my.features.desktop.quickshell = {
    enable = lib.mkEnableOption "Quickshell configuration";
  };

  config = lib.mkIf cfg.enable {
    my.features.system.audio.enable = true;

    home-manager.sharedModules = [{
      home.packages = [
        pkgs.material-symbols
        pkgs.wl-clipboard
        pkgs.wlsunset
      ];

      home.sessionVariables = {
        QS_CONFIG_PATH = "${./.}"; # Point to this directory
      };

      programs.quickshell = {
        enable = true;
        package = inputs.quickshell.packages.${pkgs.system}.default;
        systemd.enable = true;
      };
    }];
  };
}
