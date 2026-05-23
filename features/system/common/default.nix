# features/system/common.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.common;
  attic = config.my.features.cache.attic;
  attic_user = attic.user;
  attic_group = attic.group;
  deLocale = "de_DE.UTF-8";
in
{
  options.my.features.system.common = {
    enable = lib.mkEnableOption "Common system-wide settings (nix, network, time, locale, keyboard)";
  };

  options.my.role = lib.mkOption {
    type = lib.types.enum [
      "server"
      "desktop"
      "notebook"
    ];
    default = "server";
    description = "The role of this machine (server, desktop, notebook).";
  };

  options.my.features.cache.attic = {
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "User for attic config ownership and auto-push service. Set to enable attic support.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group for attic config file ownership";
    };
    autoPush = lib.mkEnableOption "Automatically push system closure to attic cache after each rebuild";
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [ "https://cache.rls.ancoris.ovh/nixfiles" ];
      trusted-public-keys = [ "nixfiles:awB26eXQsIRK6dU9tMhnDs5Ql9z+tSCy1BQL1PWX8JE=" ];
    };

    networking.networkmanager.enable = true;

    time.timeZone = "Europe/Berlin";

    services.xserver = {
      xkb.layout = "de";
    };

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

    sops.defaultSopsFile = ../../../secrets/secrets.yaml;
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    sops.secrets.attic_push_token = lib.mkIf (attic_user != null) { };
    sops.templates.attic_config = lib.mkIf (attic_user != null) {
      owner = attic_user;
      group = attic_group;
      mode = "0440";
      content = ''
        default-server = "nixfiles-server"

        [servers.nixfiles-server]
        endpoint = "https://cache.rls.ancoris.ovh"
        token = "${config.sops.placeholder.attic_push_token}"
      '';
    };

    systemd.tmpfiles.rules = lib.mkIf (attic_user != null) [
      "d /home/${attic_user}/.config/attic 0700 ${attic_user} ${attic_group} -"
      "L+ /home/${attic_user}/.config/attic/config.toml 0400 ${attic_user} ${attic_group} - /run/secrets/rendered/attic_config"
    ];

    systemd.paths.attic-push-system = lib.mkIf (attic_user != null && attic.autoPush) {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = "/run/current-system";
        Unit = "attic-push-system.service";
      };
    };

    systemd.services.attic-push-system = lib.mkIf (attic_user != null && attic.autoPush) {
      description = "Push current system closure to attic cache after rebuild";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = attic_user;
        ExecStart = "${pkgs.writeShellScript "attic-push-system" ''
          set -euo pipefail
          CLOSURE=$(${pkgs.coreutils}/bin/readlink /run/current-system)
          if [ -z "$CLOSURE" ]; then
            echo "Error: /run/current-system does not resolve" >&2
            exit 1
          fi
          ${pkgs.attic-client}/bin/attic push nixfiles "$CLOSURE"
        ''}";
      };
    };
  };
}
