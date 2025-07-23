{
  ...
}:

{
  imports = [
    ./packages.nix
    ./modules/dconf/default.nix
    ./modules/codium.nix
    ./modules/nixvim.nix
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
  
  programs = {
    home-manager.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fish.enable = true; # see note on other shells below
  };
}
