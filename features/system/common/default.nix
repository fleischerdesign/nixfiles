# features/system/common.nix
{
  config,
  lib,
  pkgs,
  inputs ? null,
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
    nix.package = pkgs.lix;

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      max-jobs = "auto";
      cores = 0;

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

    documentation.man.cache.enable = false;
    documentation.doc.enable = false;

    my.features.dev.git.enable = true;

    environment.systemPackages =
      with pkgs;
      [
        wget
        openssl
        btop
        tree
        duf
        ripgrep
      ]
      ++ lib.optionals (inputs ? nod && inputs.nod ? packages) [
        inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

    sops = {
      defaultSopsFile = ../../../secrets/secrets.yaml;
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };
}
