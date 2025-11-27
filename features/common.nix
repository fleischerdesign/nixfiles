# features/common.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.common;
  deLocale = "de_DE.UTF-8";
in
{
  options.my.features.common = {
    enable = lib.mkEnableOption "Common system-wide settings (nix, network, time, locale, keyboard)";
  };

  config = lib.mkIf cfg.enable {
    # Enable experimental features
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Network manager configuration
    networking.networkmanager.enable = true;

    # Set the timezone
    time.timeZone = "Europe/Berlin";

    # Set keyboard layout for graphical environments
    services.xserver = {
      xkb.layout = "de";
    };

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

    # Enable Nh cli helper
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/etc/nixos";
    };

    documentation.man.generateCaches = false; # Disable man cache generation

    # System packages to be installed
    environment.systemPackages = with pkgs; [
      wget
      openssl
      git
      gh
      btop
      tree
      duf
      ripgrep
    ];
  };
}
