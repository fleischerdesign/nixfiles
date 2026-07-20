{
  pkgs,
  hostname,
  lib,
  osConfig,
  ...
}:
{
  imports = [
    ./packages.nix
    ./opencode.nix
  ];

  home.username = osConfig.my.user.name;
  home.homeDirectory = "/home/${osConfig.my.user.name}";
  home.stateVersion = "24.05";

  systemd.user.startServices = "sd-switch";

  xdg.desktopEntries."ls3d-handler" = {
    name = "WBS Learnspace 3D Handler";
    exec = "/home/philipp/ls3d-handler.sh %u";
    type = "Application";
    terminal = false;
    noDisplay = true;
    mimeType = [ "x-scheme-handler/ls3d" ];
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/ls3d" = "ls3d-handler.desktop";
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    fish = {
      enable = true;
      shellAliases = {
        c = "codium";
      }
      // lib.optionalAttrs (hostname != "rollins") {
        hermes = "ssh -t ${osConfig.my.user.name}@${osConfig.my.features.system.networking.topology.hosts.rollins.tailscaleIp} hermes";
      };
    };

    home-manager.enable = true;
  };

  home.packages = [
    pkgs.nil
    pkgs.nixfmt
  ];
}
