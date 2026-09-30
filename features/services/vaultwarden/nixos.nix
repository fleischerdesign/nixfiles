{
  config,
  lib,
  pkgs,
  features,
  fleetConfigs,
  ...
}:
let
  cfg = config.my.features.services.vaultwarden;
  smtp = config.my.features.system.smtp;
  contract = config.my.contracts.provides.vaultwarden;
  oidc = contract.identity.oidc.web;
  database = config.my.contracts.consumes.vaultwarden.postgresql.main;
  systems = fleetConfigs.systems config;
  authentik = import ../authentik/lib/core.nix { inherit fleetConfigs; };
  authPublication =
    (fleetConfigs.providesOf systems.${authentik.hostName systems}).authentik.publications.web;
  identifiers = import ../../../contracts/endpoints/lib/identifiers.nix { };
  application = identifiers.endpointName "vaultwarden" oidc.publication;
  dataDir = "/var/lib/${config.systemd.services.vaultwarden.serviceConfig.StateDirectory}";
  snapshotDir = "/var/backup/vaultwarden";
  socketDir = "/run/postgresql";
  snapshot = pkgs.writeShellApplication {
    name = "vaultwarden-snapshot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.rsync
      pkgs.util-linux
      pkgs.systemd
      config.services.postgresql.package
    ];
    text = builtins.readFile ./snapshot.sh;
  };
in
{
  options.my.features.services.vaultwarden.enable =
    lib.mkEnableOption "Vaultwarden with Authentik SSO";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)
      {
        my.features.system.smtp.enable = true;
        services.vaultwarden = {
          enable = true;
          dbBackend = "postgresql";
          config = {
            DOMAIN = contract.publications.web.publicUrl;
            SMTP_HOST = smtp.host;
            SMTP_PORT = smtp.port;
            SMTP_SECURITY = if smtp.tls == "starttls" then "starttls" else "force_tls";
            SMTP_FROM = smtp.fromAddress;
            SMTP_FROM_NAME = "Vaultwarden";
            ROCKET_ADDRESS = "127.0.0.1";
            ROCKET_PORT = contract.endpoints.web.port;
            DATABASE_URL = "postgresql:///${database.database}?host=${socketDir}";

            SIGNUPS_ALLOWED = false;
            SSO_ENABLED = true;
            SSO_ONLY = true;
            SSO_SIGNUPS_ALLOWED = true;
            SSO_SIGNUPS_MATCH_EMAIL = false;
            # Authentik's application-specific email scope makes no verification claim.
            # Matching initialized non-SSO vaults by email is disabled.
            SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = true;
            SSO_AUTHORITY = "${authPublication.publicUrl}/application/o/${application}/";
            SSO_CLIENT_ID = oidc.clientId;
            SSO_SCOPES = lib.concatStringsSep " " (
              oidc.propertyMappings ++ map (mapping: mapping.scopeName) (lib.attrValues oidc.scopeMappings)
            );
            SSO_PKCE = true;
            SSO_DEBUG_TOKENS = false;

            # Admin is disabled. A store-owned empty override file also prevents a
            # writable config.json from becoming a second configuration authority.
            CONFIG_FILE = toString (pkgs.writeText "vaultwarden-config.json" "{}");
            DISABLE_ADMIN_TOKEN = false;
            IP_HEADER = "X-Forwarded-For";
            IP_HEADER_TRUSTED_PROXIES = "127.0.0.1";
            REQUIRE_DEVICE_EMAIL = false;
            SHOW_PASSWORD_HINT = false;
          };
          environmentFile = config.sops.templates."vaultwarden.env".path;
        };

        sops.secrets.${oidc.secretPath} = { };
        sops.templates."vaultwarden.env" = {
          restartUnits = [ "vaultwarden.service" ];
          content = ''
            SSO_CLIENT_SECRET=${config.sops.placeholder.${oidc.secretPath}}
            SMTP_USERNAME=${config.sops.placeholder.${smtp.usernameSecret}}
            SMTP_PASSWORD=${config.sops.placeholder.${smtp.passwordSecret}}
          '';
        };

        systemd.services.vaultwarden = {
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          restartTriggers = [ config.sops.templates."vaultwarden.env".file ];
        };

        systemd.services.vaultwarden-snapshot = {
          description = "Create a consistent Vaultwarden database and file snapshot";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe snapshot)
              dataDir
              snapshotDir
              database.database
              database.user
              socketDir
            ];
          };
        };

        my.contracts.consumes.vaultwarden.postgresql.main.database = "vaultwarden";
        my.contracts.provides.vaultwarden = {
          dependsOn = [
            "authentik"
            "postgresql"
          ];
          endpoints.web.port = 8082;
          publications.web = {
            endpoint = "web";
            scope = "public";
            subdomain = "vault";
            auth = "oidc";
            accessAuthenticated = true;
          };
          identity.oidc.web = {
            publication = "web";
            enable = true;
            clientId = "vaultwarden";
            secretPath = "services/apps/vaultwarden_oidc_secret";
            redirectPaths = [ "/identity/connect/oidc-signin" ];
            propertyMappings = [
              "openid"
              "profile"
              "offline_access"
            ];
            accessTokenValidity = "minutes=15";
            scopeMappings.email = {
              scopeName = "email";
              expression = ''
                return {"email": request.user.email}
              '';
            };
          };
          presentation.tiles.web = {
            endpoint = "web";
            description = {
              de = "Passwort-Tresor mit Authentik-Anmeldung.";
              en = "Password vault with Authentik sign-in.";
            };
            show = true;
            displayName = "Vaultwarden";
            category = "Security";
            icon = "vaultwarden";
          };
          telemetry.probes.web-http = {
            endpoint = "web";
            kind = "http";
            path = "/alive";
          };
          storage = {
            dataDirs = [ dataDir ];
            cacheDirs = [
              "${dataDir}/icon_cache"
              "${dataDir}/tmp"
            ];
          };
          backup = {
            paths = [ snapshotDir ];
            exclude = [
              dataDir
              "${snapshotDir}/.staging"
            ];
            preBackup = "${pkgs.systemd}/bin/systemctl start vaultwarden-snapshot.service";
          };
        };
      }
    ]
  );
}
