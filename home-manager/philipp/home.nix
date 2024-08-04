{ config, pkgs, nix-vscode-extensions, ... }:

{
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
  programs.home-manager.enable = true;

  home.packages = [
    pkgs.google-chrome
    pkgs.spotify
    pkgs.gnomeExtensions.blur-my-shell
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.caffeine
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gimp
    pkgs.blackbox-terminal
    pkgs.figma-linux
    pkgs.figma-agent
    pkgs.obsidian
    pkgs.telegram-desktop
    (pkgs.callPackage ../../packages/lychee-slicer {})

  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  programs.starship = {
    enable = true;
    settings = {
          # add_newline = false;

          # character = {
          #   success_symbol = "[➜](bold green)";
          #   error_symbol = "[➜](bold red)";
          # };

          # package.disabled = true;
        };
  };

  dconf = {
    enable = true;

    settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

    settings."org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = with pkgs.gnomeExtensions; [
        blur-my-shell.extensionUuid
        gsconnect.extensionUuid
        caffeine.extensionUuid
        dash-to-dock.extensionUuid
      ];
    };
  };

  programs.vscode = {
  enable = true;
  package = pkgs.vscodium;
  mutableExtensionsDir = false;
  extensions = with pkgs.open-vsx; [
    continue.continue
    bbenoist.nix
    prisma.prisma
    ms-python.python
    vue.volar
  ];
};

}
