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
  ];

  home.username = "philipp";
  home.homeDirectory = "/home/philipp";
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
        hermes = "ssh -t philipp@${osConfig.my.features.system.networking.topology.hosts.rollins.tailscaleIp} hermes";
      };
      interactiveShellInit = ''
        set -gx SOPS_AGE_KEY_FILE /home/philipp/.config/sops/age/keys.txt
      '';
    };

    home-manager.enable = true;
  };

  home.packages = [
    pkgs.nil
    pkgs.nixfmt
  ];
}
