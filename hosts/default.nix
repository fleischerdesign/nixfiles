{ pkgs, ... }:

let
  # Define common locale settings for better readability
  deLocale = "de_DE.UTF-8";
in
{
  # Enable experimental features
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Network manager configuration
  networking.networkmanager.enable = true;
  # Set the timezone
  time.timeZone = "Europe/Berlin";

  # Internationalization settings
  i18n.defaultLocale = deLocale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = deLocale;
    LC_IDENTIFICATION = deLocale;
    LC_MEASUREMENT = deLocale;
    LC_MONETARY = deLocale;
    LC_NAME = deLocale;
    LC_NUMERIC = deLocale;
    LC_PAPER = deLocale;
    LC_TELEPHONE = deLocale;
    LC_TIME = deLocale;
  };
  console.keyMap = "de";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable adb
  programs.adb.enable = true;

  # Enable Fish shell
  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  services.lorri.enable = true;
  programs.direnv = {
    enable = true;
    enableFishIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };

  # Enable Docker
  virtualisation.docker.enable = true;
  users.users.philipp.extraGroups = [ "docker" ];
  # System packages to be installed
  environment.systemPackages = with pkgs; [
    wget
    openssl
    git
    gh
    btop
  ];
}
