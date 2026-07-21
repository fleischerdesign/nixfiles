{
  pkgs,
  osConfig,
  inputs,
  ...
}:
{
  imports = [
    ./packages.nix
    ./opencode.nix
    ./fish.nix
    inputs.nixcord.homeModules.nixcord
  ];

  home.username = osConfig.my.user.name;
  home.homeDirectory = "/home/${osConfig.my.user.name}";
  home.stateVersion = "24.05";

  systemd.user.startServices = "sd-switch";

  xdg.desktopEntries."ls3d-handler" = {
    name = "WBS Learnspace 3D Handler";
    exec = "/home/${osConfig.my.user.name}/ls3d-handler.sh %u";
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

    home-manager.enable = true;
  };

  home.packages = [
    pkgs.nil
    pkgs.nixfmt
  ];
}
