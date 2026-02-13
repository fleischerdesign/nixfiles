{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.ntfy;
in
{
  options.my.features.services.ntfy = {
    enable = lib.mkEnableOption "ntfy-sh notification service";
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.\${config.my.features.services.caddy.baseDomain}";
        listen-http = "127.0.0.1:8082";
        auth-file = "/var/lib/ntfy-sh/auth.db";
        auth-default-access = "deny-all";
        behind-proxy = true;
        # Erlaubt das Hochladen von Anhängen (optional, aber nützlich für Alerts mit Bildern)
        attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
      };
      # Hier kommen NTFY_AUTH_USERS etc. rein
      environmentFile = config.sops.secrets.ntfy_env.path;
    };

    # Verzeichnis für Anhänge sicherstellen
    systemd.tmpfiles.rules = [
      "d /var/lib/ntfy-sh/attachments 0700 ntfy-sh ntfy-sh -"
    ];

    # Expose via Caddy (ohne Authentik, ntfy macht eigenes Auth)
    my.features.services.caddy.exposedServices.ntfy = {
      port = 8082;
      auth = false; 
    };

    # Sops Secret definieren
    sops.secrets.ntfy_env = {
      owner = "ntfy-sh";
    };
  };
}
