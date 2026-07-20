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

      post-build-hook = pkgs.writeShellScript "attic-push-hook" ''
        set -e
        STAMP_DIR="/var/lib/attic-push-stamps"
        mkdir -p "$STAMP_DIR"

        for out in $2; do
          case "$out" in
            *nixos-system-*)
              stamp="$STAMP_DIR/$(basename "$out")"
              if [ ! -f "$stamp" ]; then
                ${pkgs.attic-client}/bin/attic push nixfiles "$out" 2>/dev/null && touch "$stamp" || true
              fi
              ;;
          esac
        done
      '';
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

    sops.secrets.attic_push_token = { };

    sops.templates.attic_root_config = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        default-server = "nixfiles-server"

        [servers.nixfiles-server]
        endpoint = "https://cache.rls.ancoris.ovh"
        token = "${config.sops.placeholder.attic_push_token}"
      '';
    };

    systemd.tmpfiles.rules = [
      "d /root/.config/attic 0700 root root -"
      "L+ /root/.config/attic/config.toml 0400 root root - /run/secrets/rendered/attic_root_config"
    ];
  };
}
