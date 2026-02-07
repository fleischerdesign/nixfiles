{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.mail;
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
        
        # 0.15 Store Definitions
        store.data = {
          type = "sql";
          driver = "postgres";
          url = dbUrl;
        };
        store.lookup = {
          type = "sql";
          driver = "postgres";
          url = dbUrl;
        };
        store.directory = {
          type = "sql";
          driver = "postgres";
          url = dbUrl;
        };
        store.blob = {
          type = "fs";
          path = "/var/lib/stalwart-mail/blobs";
        };
        store.cache = {
          type = "redis";
          url = "redis://127.0.0.1:6379";
        };

        # Domains
        directory.internal.domains = [ "ancoris.ovh" "fleischer.design" ];

        # Use internal SQL directory for authentication and lookup
        session.auth.directory = "internal";
        session.rcpt.directory = "internal";

        # Spam filter
        spam.classifier.store = "data";
        spam.training.store = "data";

        # SMTP Relay (Brevo)
        remote.relay.brevo = {
          host = "smtp-relay.brevo.com";
          port = 587;
        };
        session.rcpt.relay = "brevo";

        # Management Listener with OIDC option
        server.listener.management = {
          bind = [ "127.0.0.1:9081" ];
          protocol = "http";
          oidc = {
            issuer = "https://auth.ancoris.ovh/application/o/stalwart/";
            client-id = "%{file:${config.sops.secrets.stalwart_oidc_id.path}}%";
            client-secret = "%{file:${config.sops.secrets.stalwart_oidc_secret.path}}%";
            scopes = [ "openid" "profile" "email" ];
          };
        };

        # Fallback Admin
        authentication.fallback-admin = {
          user = "admin";
          secret = "%{file:${config.sops.secrets.mail_admin_password.path}}%";
        };
      };

      credentials = {
        "remote.relay.brevo.auth.user" = config.sops.secrets.brevo_smtp_user.path;
        "remote.relay.brevo.auth.secret" = config.sops.secrets.brevo_smtp_key.path;
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

    systemd.tmpfiles.rules = [
      "d /var/lib/stalwart-mail 0750 stalwart-mail stalwart-mail -"
      "d /var/lib/stalwart-mail/blobs 0750 stalwart-mail stalwart-mail -"
    ];

    # Secrets
    sops.secrets.brevo_smtp_user = { owner = "stalwart-mail"; };
    sops.secrets.brevo_smtp_key = { owner = "stalwart-mail"; };
    sops.secrets.mail_admin_password = { owner = "stalwart-mail"; };
    sops.secrets.stalwart_oidc_id = { owner = "stalwart-mail"; };
    sops.secrets.stalwart_oidc_secret = { owner = "stalwart-mail"; };
  };
}