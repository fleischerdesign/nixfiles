{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.mail;
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
        
        # Domains
        directory.internal.domains = [ "ancoris.ovh" "fleischer.design" ];

        # Storage with PostgreSQL
        storage.data = {
          type = "sql";
          driver = "postgres";
          url = "postgresql://stalwart@%2Frun%2Fpostgresql/stalwart";
        };
        storage.lookup = {
          type = "sql";
          driver = "postgres";
          url = "postgresql://stalwart@%2Frun%2Fpostgresql/stalwart";
        };
        storage.blob = {
          type = "fs";
          path = "/var/lib/stalwart-mail/blobs";
        };

        # Caching with Redis
        storage.cache = {
          type = "redis";
          url = "redis://127.0.0.1:6379";
        };

        # Spam filter storage
        spam.classifier.path = "/var/lib/stalwart-mail/spam/filter.classifier";

        # SMTP Relay (Brevo)
        remote.relay.brevo = {
          host = "smtp-relay.brevo.com";
          port = 587;
        };

        session.rcpt.relay = "brevo";

        # Management UI
        server.listener.http = {
          bind = [ "127.0.0.1:9081" ];
          protocol = "http";
        };
      };

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

    # Secrets
    sops.secrets.brevo_smtp_user = { owner = "stalwart-mail"; };
    sops.secrets.brevo_smtp_key = { owner = "stalwart-mail"; };
    sops.secrets.mail_admin_user = { owner = "stalwart-mail"; };
    sops.secrets.mail_admin_password = { owner = "stalwart-mail"; };
  };
}
