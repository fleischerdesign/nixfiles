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

  # Enable Nh cli helper
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/etc/nixos";
  };

  # Enable Fish shell
  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;
  documentation.man.generateCaches = false; # Disable man cache generation

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
