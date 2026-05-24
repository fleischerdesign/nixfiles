{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.attic.client;
in
{
  options.my.features.services.attic.client = {
    enable = lib.mkEnableOption "attic binary cache client";
    user = lib.mkOption {
      type = lib.types.str;
      description = "User for attic config ownership and auto-push service.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group for attic config file ownership";
    };
    autoPush = lib.mkEnableOption "Automatically push system closure to attic cache after each rebuild";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.attic_push_token = { };
    sops.templates.attic_config = {
      owner = cfg.user;
      inherit (cfg) group;
      mode = "0440";
      content = ''
        default-server = "nixfiles-server"

        [servers.nixfiles-server]
        endpoint = "https://cache.rls.ancoris.ovh"
        token = "${config.sops.placeholder.attic_push_token}"
      '';
    };

    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.config/attic 0700 ${cfg.user} ${cfg.group} -"
      "L+ /home/${cfg.user}/.config/attic/config.toml 0400 ${cfg.user} ${cfg.group} - /run/secrets/rendered/attic_config"
    ];

    system.activationScripts.atticPush = lib.mkIf cfg.autoPush ''
      CLOSURE="$(${pkgs.coreutils}/bin/readlink -f /run/current-system)"
      if [ -n "$CLOSURE" ]; then
        runuser -u ${cfg.user} -- ${pkgs.attic-client}/bin/attic push nixfiles "$CLOSURE" &
      fi
    '';
  };
}
