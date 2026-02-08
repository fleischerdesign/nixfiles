{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.mail;
  certDir = "/var/lib/stalwart-mail/certs";
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
        server.hostname = "mail.ancoris.ovh";
        
        # Force local configuration for managed sections
        config.local-keys = [
          "store.*"
          "storage.*"
          "directory.authentik.*"
          "server.*"
          "session.*"
          "remote.*"
          "authentication.fallback-admin.*"
          "certificate.default.*"
          "lookup.*"
          "spam.*"
        ];

        certificate."default" = {
          cert = "%{file:${certDir}/mail.crt}%";
          private-key = "%{file:${certDir}/mail.key}%";
          default = true;
        };

        server.tls = {
          certificate = "default";
          enable = true;
        };

        lookup.default = {
          hostname = "mail.ancoris.ovh";
          domain = "ancoris.ovh";
        };

        # 1. PostgreSQL Store via TCP
        store."db" = {
          type = "postgresql";
          host = "127.0.0.1";
          port = 5432;
          database = "stalwart";
          user = "stalwart";
          password = "%{file:/run/credentials/stalwart.service/db_password}%";
          tls.enable = false;
          pool.max-connections = 10;
        };

        # 2. Redis Store
        store."redis" = {
          type = "redis";
          redis-type = "single";
          url = "redis://127.0.0.1:6379";
        };

        # Storage Assignments
        storage.data = "db";
        storage.lookup = "db";
        storage.fts = "db";
        storage.blob = "db";
        storage.directory = "authentik"; 

        # LDAP Directory Configuration with CamelCase attributes
        directory."authentik" = {
          type = "ldap";
          url = "ldap://127.0.0.1:3389";
          base-dn = "dc=ldap,dc=goauthentik,dc=io";
          bind.dn = "cn=stalwart,ou=users,dc=ldap,dc=goauthentik,dc=io";
          bind.secret = "%{file:/run/credentials/stalwart.service/ldap_password}%";
          bind.auth.method = "lookup";
          
          # Use CamelCase attributes to avoid Stalwart filter parser bugs
          filter.name = "(&(objectClass=inetOrgPerson)(cn=?))";
          filter.email = "(&(objectClass=inetOrgPerson)(|(stalwartMail=?)(stalwartAliases=?)))";
          
          attributes = {
            name = "cn";
            email = "stalwartMail"; 
            email-alias = "stalwartAliases";
            groups = "memberOf";
            secret-changed = "pwdChangedTime";
          };
        };

        # SMTP Relay (Brevo)
        remote.relay."brevo" = {
          host = "smtp-relay.brevo.com";
          port = 587;
        };
        session.rcpt.relay = "'brevo'";

        # MTA Signing
        mta.sign.dkim = {
          enable = true;
          selector = "202602r";
        };

        # Listeners
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

        server.listener.smtp = { bind = [ "[::]:25" ]; protocol = "smtp"; hostname = "mail.ancoris.ovh"; };
        server.listener.submissions = { bind = [ "[::]:465" ]; protocol = "smtp"; tls.implicit = true; hostname = "mail.ancoris.ovh"; };
        server.listener.submission = { bind = [ "[::]:587" ]; protocol = "smtp"; tls.enable = true; hostname = "mail.ancoris.ovh"; };
        server.listener.imaps = { bind = [ "[::]:993" ]; protocol = "imap"; tls.implicit = true; hostname = "mail.ancoris.ovh"; };
        server.listener.imap = { bind = [ "[::]:143" ]; protocol = "imap"; tls.enable = true; hostname = "mail.ancoris.ovh"; };

        authentication.fallback-admin = {
          user = "admin";
          secret = "%{file:${config.sops.secrets.mail_admin_password.path}}%";
        };
      };

      credentials = {
        "remote.relay.brevo.auth.user" = config.sops.secrets.brevo_smtp_user.path;
        "remote.relay.brevo.auth.secret" = config.sops.secrets.brevo_smtp_key.path;
        "ldap_password" = config.sops.secrets.stalwart_ldap_password.path;
        "db_password" = config.sops.secrets.stalwart_db_password.path;
      };
    };

    # One-shot service to ensure postgres user has the correct password
    systemd.services.stalwart-db-init = {
      description = "Ensure Stalwart DB user has correct password";
      after = [ "postgresql.service" ];
      before = [ "stalwart.service" ];
      wantedBy = [ "stalwart.service" ];
      serviceConfig = { Type = "oneshot"; User = "postgres"; };
      script = ''
        ${config.services.postgresql.package}/bin/psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='stalwart'" | grep -q 1 || exit 0
        ${config.services.postgresql.package}/bin/psql -c "ALTER USER stalwart WITH PASSWORD '$(cat ${config.sops.secrets.stalwart_db_password.path})';"
      '';
    };

    systemd.services.stalwart-cert-deploy = {
      description = "Deploy Caddy certificates to Stalwart";
      after = [ "caddy.service" ];
      before = [ "stalwart.service" ];
      wantedBy = [ "stalwart.service" ];
      serviceConfig = { Type = "oneshot"; User = "root"; };
      script = ''
        mkdir -p ${certDir}
        cp /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.ancoris.ovh/mail.ancoris.ovh.crt ${certDir}/mail.crt
        cp /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.ancoris.ovh/mail.ancoris.ovh.key ${certDir}/mail.key
        chown -R stalwart-mail:stalwart-mail ${certDir}
        chmod 750 ${certDir}
        chmod 640 ${certDir}/*
      '';
    };

    services.postgresql = {
      ensureDatabases = [ "stalwart" ];
      ensureUsers = [{ name = "stalwart"; ensureDBOwnership = true; }];
    };

    my.features.services.caddy.exposedServices = {
      "mail" = { port = 9081; fullDomain = "mail.ancoris.ovh"; };
    };

    systemd.tmpfiles.rules = [ "d /var/lib/stalwart-mail 0750 stalwart-mail stalwart-mail -" ];

    sops.secrets.brevo_smtp_user = { owner = "stalwart-mail"; };
    sops.secrets.brevo_smtp_key = { owner = "stalwart-mail"; };
    sops.secrets.mail_admin_password = { owner = "stalwart-mail"; };
    sops.secrets.stalwart_oidc_id = { owner = "stalwart-mail"; };
    sops.secrets.stalwart_oidc_secret = { owner = "stalwart-mail"; };
    sops.secrets.stalwart_ldap_password = { owner = "stalwart-mail"; };
    sops.secrets.stalwart_db_password = { owner = "postgres"; };
  };
}