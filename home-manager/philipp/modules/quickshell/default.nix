{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.homeManager.modules.quickshell.enable {
    home.packages = [ pkgs.material-symbols ];
    programs.quickshell = {
      enable = true;
      activeConfig = "/etc/nixos/home-manager/philipp/modules/quickshell";
      systemd.enable = true;
    };
  };
}
