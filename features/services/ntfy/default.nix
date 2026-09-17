{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.ntfy;
in
{
  options.my.features.services.ntfy = {
    enable = lib.mkEnableOption "ntfy-sh notification service";

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = config.my.user.primary or "admin";
      description = "Primary admin username for ntfy auth tokens.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secret für den Token (wird von Grafana mitgenutzt)
    sops.secrets."services/monitoring/grafana_ntfy_token" = {
      owner = "ntfy-sh";
      group = "grafana";
      mode = "0440"; # Nur Besitzer und Gruppe dürfen lesen
    };
    sops.secrets."infra/ntfy_users" = {
      owner = "ntfy-sh";
    };

    # Template für ntfy env, um Token deklarativ einzubauen
    sops.templates."ntfy.env".content = ''
      NTFY_AUTH_USERS="${config.sops.placeholder."infra/ntfy_users"}"
      NTFY_AUTH_TOKENS="${cfg.adminUser}:${
        config.sops.placeholder."services/monitoring/grafana_ntfy_token"
      }:Grafana"
    '';

    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://push.vyrx.de";
        listen-http = "127.0.0.1:8083";
        auth-file = "/var/lib/ntfy-sh/auth.db";
        auth-default-access = "deny-all";
        behind-proxy = true;
        enable-login = true;
        require-login = true;
        log-level = "info";
        attachment-cache-dir = "/var/cache/ntfy-sh/attachments";
      };
      environmentFile = config.sops.templates."ntfy.env".path;
    };

    systemd.services.ntfy-sh.serviceConfig.CacheDirectory = "ntfy-sh";

    my.endpoints.ntfy = {
      host = config.networking.hostName;
      port = 8083;
      proxy = {
        enable = true;
        subdomain = "ntfy";
      };
    };
  };
}
