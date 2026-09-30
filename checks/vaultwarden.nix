{
  pkgs,
  lib,
  self,
  ...
}:
let
  hosts = lib.filterAttrs (
    _: host: host.config.my.features.services.vaultwarden.enable
  ) self.nixosConfigurations;
  cfg = hosts.cld-edge-01.config;
  contract = cfg.my.contracts.provides.vaultwarden;
  settings = cfg.services.vaultwarden.config;
  unit = cfg.systemd.services.vaultwarden.serviceConfig;
  oidc = contract.identity.oidc.web;
  database = cfg.my.contracts.consumes.vaultwarden.postgresql.main;
  vhost = cfg.services.caddy.virtualHosts.${contract.publications.web.canonicalDomain}.extraConfig;
  compilerAccepts =
    publication:
    let
      fixture = cfg // {
        my = cfg.my // {
          contracts = cfg.my.contracts // {
            provides = cfg.my.contracts.provides // {
              vaultwarden = contract // {
                publications.web = publication;
              };
            };
          };
        };
      };
      compiler = import ../features/services/authentik/server/blueprints.nix {
        config = cfg;
        inherit lib pkgs;
        blueprintLib = import ../features/services/authentik/lib/blueprint.nix { inherit lib; };
        fleetConfigs = (import ../lib/fleet-configs.nix { inherit lib; }) // {
          systems = _: self.nixosConfigurations // { cld-edge-01.config = fixture; };
        };
      };
    in
    (builtins.tryEval compiler.dir.drvPath).success;
  claims = {
    "one-selected-host" = builtins.attrNames hosts == [ "cld-edge-01" ];
    "public-name-is-canonical" =
      contract.publications.web.scope == "public"
      && settings.DOMAIN == contract.publications.web.publicUrl;
    "only-native-sso" =
      settings.SSO_ENABLED && settings.SSO_ONLY && settings.SSO_PKCE && !settings.SIGNUPS_ALLOWED;
    "explicit-human-audience" =
      contract.publications.web.accessAuthenticated && contract.publications.web.accessGroups == [ ];
    "no-email-account-linking" = !settings.SSO_SIGNUPS_MATCH_EMAIL;
    "client-and-callback-agree" =
      settings.SSO_CLIENT_ID == oidc.clientId
      && oidc.redirectUris == [ "${settings.DOMAIN}/identity/connect/oidc-signin" ];
    "no-forward-auth-on-client-api" =
      !lib.hasInfix "forward_auth" vhost
      && lib.hasInfix "127.0.0.1:${toString settings.ROCKET_PORT}" vhost;
    "local-database-owner" =
      database.ensureDBOwnership
      && lib.any (
        user: user.name == database.user && user.ensureDBOwnership
      ) cfg.services.postgresql.ensureUsers;
    "no-admin-or-smtp" =
      !(settings ? ADMIN_TOKEN) && !settings.DISABLE_ADMIN_TOKEN && !(settings ? SMTP_HOST);
    "secret-is-runtime-only" =
      !(settings ? SSO_CLIENT_SECRET)
      &&
        lib.hasInfix cfg.sops.placeholder.${oidc.secretPath}
          cfg.sops.templates."vaultwarden.env".content;
    "hardening-is-delivered" =
      unit.ProtectSystem == "strict" && unit.ProtectHome && unit.NoNewPrivileges && unit.UMask == "0077";
    "backup-has-a-consistency-hook" =
      contract.backup.preBackup != null
      && lib.elem contract.backup.preBackup cfg.my.contracts.projections.backup.preBackup
      && lib.elem "/var/lib/${unit.StateDirectory}" contract.backup.exclude;
    "other-hosts-stay-disabled" = builtins.all (
      name: name == "cld-edge-01" || !self.nixosConfigurations.${name}.config.services.vaultwarden.enable
    ) (builtins.attrNames self.nixosConfigurations);
    "mixed-audience-is-rejected" =
      !compilerAccepts (contract.publications.web // { accessGroups = [ "family" ]; });
    "implicit-open-audience-is-rejected" =
      !compilerAccepts (contract.publications.web // { accessAuthenticated = false; });
  };
  violated = lib.attrNames (lib.filterAttrs (_: holds: !holds) claims);
  settingsFile = pkgs.writeText "vaultwarden-test-settings.json" (
    builtins.toJSON (
      settings
      // {
        WEB_VAULT_FOLDER = "${cfg.services.vaultwarden.webVaultPackage}/share/vaultwarden/vault";
      }
    )
  );
  caddyFile = pkgs.writeText "vaultwarden-test.Caddyfile" ''
    ${contract.publications.web.canonicalDomain} {
      ${vhost}
    }
  '';
in
if violated != [ ] then
  throw "vaultwarden: violated claims: ${lib.concatStringsSep ", " violated}"
else
  pkgs.runCommandLocal "vaultwarden-check"
    {
      nativeBuildInputs = [
        (pkgs.python3.withPackages (p: [ p.pyyaml ]))
        cfg.services.postgresql.package
        pkgs.rsync
        pkgs.bash
        cfg.services.caddy.package
      ];
    }
    ''
      cp ${caddyFile} Caddyfile
      chmod u+w Caddyfile
      caddy fmt --overwrite Caddyfile
      test -e ${cfg.systemd.units."vaultwarden-snapshot.service".unit}
      caddy adapt --config Caddyfile --adapter caddyfile > caddy.json 2> caddy.log
      cat caddy.log >&2
      python3 ${./vaultwarden.py} \
        ${cfg.my.features.services.authentik.server.blueprintsDir} \
        ${settingsFile} \
        ${lib.getExe (cfg.services.vaultwarden.package.override { dbBackend = "postgresql"; })} \
        ${../features/services/vaultwarden/snapshot.sh}
      touch "$out"
    ''
