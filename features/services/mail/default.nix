{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.mail;
  # Common DB URL
  dbUrl = "postgresql://stalwart@%2Frun%2Fpostgresql/stalwart";
in
{
  options.my.features.services.mail = {
    enable = lib.mkEnableOption "Stalwart Mail Server";
  };

  config = lib.mkIf cfg.enable {
    services.stalwart = {
      enable = true;
      openFirewall = true;

      settings = {
        server.hostname = "mackaye.ancoris.ovh";
        
        # 1. Define Backends
        storage.pg = {
          type = "sql";
          driver = "postgres";
          url = dbUrl;
        };
        storage.red = {
          type = "redis";
          url = "redis://127.0.0.1:6379";
        };
        storage.fs = {
          type = "fs";
          path = "/var/lib/stalwart-mail/blobs";
        };

        # 2. Map Purposes to Backends
        storage.data = "pg";
        storage.lookup = "pg";
        storage.directory = "pg";
        storage.queue = "pg";
        storage.blob = "fs";
        storage.cache = "red";

        # 3. Domains
        directory.internal.domains = [ "ancoris.ovh" "fleischer.design" ];

        # 4. Spam filter
        spam.classifier.store = "pg";
        spam.training.store = "pg";

        # 5. SMTP Relay (Brevo)
        remote.relay.brevo = {
          host = "smtp-relay.brevo.com";
          port = 587;
        };
        session.rcpt.relay = "brevo";

        # 6. Listeners
        server.listener.http = {
          bind = [ "127.0.0.1:9081" ];
          protocol = "http";
        };
      };

      # Pass secrets as files (Stalwart reads them via %{file:path}%)
      credentials = {
        "remote.relay.brevo.auth.user" = config.sops.secrets.brevo_smtp_user.path;
        "remote.relay.brevo.auth.secret" = config.sops.secrets.brevo_smtp_key.path;
        "authentication.fallback-admin.user" = config.sops.secrets.mail_admin_user.path;
        "authentication.fallback-admin.secret" = config.sops.secrets.mail_admin_password.path;
      };
    };

    # Ensure PostgreSQL DB exists
    services.postgresql = {
      ensureDatabases = [ "stalwart" ];
      ensureUsers = [
        {
          name = "stalwart";
          ensureDBOwnership = true;
        }
      ];
    };

    # Caddy Reverse Proxy
    my.features.services.caddy.exposedServices = {
      "mail" = {
        port = 9081;
        fullDomain = "mail.ancoris.ovh";
      };
    };

    # Directory Setup
    systemd.tmpfiles.rules = [
      "d /var/lib/stalwart-mail 0750 stalwart-mail stalwart-mail -"
      "d /var/lib/stalwart-mail/blobs 0750 stalwart-mail stalwart-mail -"
    ];

    # Secrets
    sops.secrets.brevo_smtp_user = { owner = "stalwart-mail"; };
    sops.secrets.brevo_smtp_key = { owner = "stalwart-mail"; };
    sops.secrets.mail_admin_user = { owner = "stalwart-mail"; };
    sops.secrets.mail_admin_password = { owner = "stalwart-mail"; };
  };
}