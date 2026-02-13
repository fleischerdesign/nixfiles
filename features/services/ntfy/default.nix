{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.ntfy;
in
{
  options.my.features.services.ntfy = {
    enable = lib.mkEnableOption "ntfy-sh notification service";
  };

  config = lib.mkIf cfg.enable {
    # Secret für den Token (wird von Grafana mitgenutzt)
    sops.secrets.grafana_ntfy_token = { 
      owner = "ntfy-sh";
      group = "grafana";
      mode = "0440"; # Nur Besitzer und Gruppe dürfen lesen
    };
    sops.secrets.ntfy_users = { owner = "ntfy-sh"; };

    # Template für ntfy env, um Token deklarativ einzubauen
    sops.templates."ntfy.env".content = ''
      NTFY_AUTH_USERS="${config.sops.placeholder.ntfy_users}"
      NTFY_AUTH_TOKENS="philipp:${config.sops.placeholder.grafana_ntfy_token}:Grafana"
    '';

    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.${config.my.features.services.caddy.baseDomain}";
        listen-http = "127.0.0.1:8083";
        auth-file = "/var/lib/ntfy-sh/auth.db";
        auth-default-access = "deny-all";
        behind-proxy = true;
        enable-login = true;
        require-login = true;
        log-level = "trace";
        attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
      };
      environmentFile = config.sops.templates."ntfy.env".path;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/ntfy-sh/attachments 0700 ntfy-sh ntfy-sh -"
    ];

    my.features.services.caddy.exposedServices.ntfy = {
      port = 8083;
      auth = false; 
    };
  };
}