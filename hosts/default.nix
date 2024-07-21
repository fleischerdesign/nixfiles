{ config, pkgs, inputs, nix-vscode-extensions, ... }:

let
  # Define common locale settings for better readability
  deLocale = "de_DE.UTF-8";
in
{
  # Enable experimental features
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use overlays for VSCode extensions
    nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ];

  # Boot loader configuration
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

  # Network manager configuration
    networking.networkmanager.enable = true;
  # Set the timezone
  time.timeZone = "Europe/Berlin";

  # Internationalization settings
  i18n.defaultLocale = deLocale;
  i18n.extraLocaleSettings = pkgs.lib.mkAttrs([
    "LC_ADDRESS" deLocale
    "LC_IDENTIFICATION" deLocale
    "LC_MEASUREMENT" deLocale
    "LC_MONETARY" deLocale
    "LC_NAME" deLocale
    "LC_NUMERIC" deLocale
    "LC_PAPER" deLocale
    "LC_TELEPHONE" deLocale
    "LC_TIME" deLocale
  ]);
  console.keyMap = "de";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable adb
  programs.adb.enable = true;

  # System packages to be installed
  environment.systemPackages = with pkgs; [
    wget
    openssl
    git
    gh
    nodejs
  ];
}