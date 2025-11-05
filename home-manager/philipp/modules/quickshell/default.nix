{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.homeManager.modules.quickshell.enable {
    home.packages = [
      pkgs.material-symbols
      pkgs.wl-clipboard
    ];

    home.sessionVariables = {
      QS_CONFIG_PATH = "/etc/nixos/home-manager/philipp/modules/quickshell/";
    };

    programs.quickshell = {
      enable = true;
      #activeConfig = "/etc/nixos/home-manager/philipp/modules/quickshell";
      systemd.enable = true;
    };
  };
}
