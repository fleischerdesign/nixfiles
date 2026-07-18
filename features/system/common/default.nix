# features/system/common.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.common;
  deLocale = "de_DE.UTF-8";
in
{
  options = {
    my = {
      features.system.common = {
        enable = lib.mkEnableOption "Common system-wide settings (nix, network, time, locale, keyboard)";
      };

      role = lib.mkOption {
        type = lib.types.enum [
          "server"
          "desktop"
          "notebook"
        ];
        default = "server";
        description = "The role of this machine (server, desktop, notebook).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      trusted-users = [
        "root"
        "@wheel"
        "hermes"
      ];

      substituters = [ "https://cache.rls.ancoris.ovh/nixfiles" ];
      trusted-public-keys = [ "nixfiles:awB26eXQsIRK6dU9tMhnDs5Ql9z+tSCy1BQL1PWX8JE=" ];
    };

    networking.networkmanager.enable = true;

    time.timeZone = "Europe/Berlin";

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

    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/etc/nixos";
    };

    documentation.man.cache.enable = false;
    documentation.doc.enable = false;

    my.features.dev.git = {
      enable = true;
      users = [
        {
          username = "philipp";
          gitName = "Philipp Fleischer";
          gitEmail = "philipp@fleischer.design";
        }
      ];
    };

    environment.systemPackages = with pkgs; [
      wget
      openssl
      btop
      tree
      duf
      ripgrep
    ];

    sops = {
      defaultSopsFile = ../../../secrets/secrets.yaml;
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };
}
