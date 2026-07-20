# features/services/attic/client/default.nix
# Attic binary cache client configuration with optional background auto-push service.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.attic.client;

  pushScript = pkgs.writeShellApplication {
    name = "attic-auto-push";
    runtimeInputs = [
      pkgs.attic-client
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.libnotify
    ];
    text = ''
      set -euo pipefail

      STAMP_DIR="/var/lib/attic-push-stamps"
      mkdir -p "$STAMP_DIR"

      CURRENT_SYSTEM="$(readlink -f /run/current-system)"
      STAMP="$STAMP_DIR/$(basename "$CURRENT_SYSTEM")"

      if [ ! -f "$STAMP" ]; then
        echo "Pushing current system closure $CURRENT_SYSTEM to Attic cache..."
        for i in 1 2 3; do
          if attic push nixfiles "$CURRENT_SYSTEM"; then
            touch "$STAMP"
            echo "Successfully pushed $CURRENT_SYSTEM to Attic cache."
            exit 0
          fi
          echo "Attempt $i failed, retrying in 5 seconds..."
          sleep 5
        done
        echo "Network or Attic server unreachable, skipping background push for now."
      else
        echo "Current system closure $CURRENT_SYSTEM is already cached."
      fi
    '';
  };
in
{
  options.my.features.services.attic.client = {
    enable = lib.mkEnableOption "attic binary cache client";
    user = lib.mkOption {
      type = lib.types.str;
      default = config.my.user.name;
      description = "User for attic config ownership.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group for attic config file ownership.";
    };
    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.rls.ancoris.ovh";
      description = "Attic cache server endpoint URL.";
    };
    autoPush = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically push system closure to Attic binary cache in the background after system switch.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.attic_push_token = { };

    sops.templates.attic_user_config = {
      owner = cfg.user;
      inherit (cfg) group;
      mode = "0440";
      content = ''
        default-server = "nixfiles-server"

        [servers.nixfiles-server]
        endpoint = "${cfg.endpoint}"
        token = "${config.sops.placeholder.attic_push_token}"
      '';
    };

    sops.templates.attic_root_config = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        default-server = "nixfiles-server"

        [servers.nixfiles-server]
        endpoint = "${cfg.endpoint}"
        token = "${config.sops.placeholder.attic_push_token}"
      '';
    };

    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.config/attic 0700 ${cfg.user} ${cfg.group} -"
      "L+ /home/${cfg.user}/.config/attic/config.toml 0400 ${cfg.user} ${cfg.group} - /run/secrets/rendered/attic_user_config"
      "d /root/.config/attic 0700 root root -"
      "L+ /root/.config/attic/config.toml 0400 root root - /run/secrets/rendered/attic_root_config"
    ];

    systemd.services.attic-auto-push = lib.mkIf cfg.autoPush {
      description = "Asynchronous Attic Binary Cache Push Service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      wants = [
        "network-online.target"
        "tailscaled.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pushScript}/bin/attic-auto-push";
        Nice = 19;
        IOSchedulingClass = "idle";
        RemainAfterExit = false;
      };
    };
  };
}
