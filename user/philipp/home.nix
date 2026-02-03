{
  config, # Added config to the function arguments
  pkgs,
  ...
}:

{
  imports = [
    ./packages.nix
    # Other user-specific modules will be imported here as they are refactored
  ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "philipp";
  home.homeDirectory = "/home/philipp";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
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
