# features/services/zennotes/nixos.nix
# ZenNotes server: a single Go binary serving the web client and API over a
# plain-Markdown vault. The vault is the source of truth; the service only
# exposes it. Caddy terminates TLS through the service contract.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.zennotes;

  # The token never reaches the environment file or the Nix store. systemd
  # copies the SOPS secret into the unit's credential directory, which is
  # readable only by the service user.
  start = pkgs.writeShellScript "zennotes-server-start" ''
    set -eu
    export ZENNOTES_AUTH_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/auth-token")"
    exec ${pkgs.custom.zennotes-server}/bin/zennotes-server
  '';
in
{
  options.my.features.services.zennotes = {
    enable = lib.mkEnableOption "ZenNotes server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7878;
      description = "Loopback port the ZenNotes server listens on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zennotes";
      description = "Persistent state and configuration directory.";
    };

    vaultDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zennotes/vault";
      description = "Directory holding the Markdown vault.";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "notes";
      description = "Public subdomain below the fleet zone.";
    };

    authTokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "services/zennotes/auth_token";
      description = "SOPS key holding the server bearer token.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.zennotes = {
      isSystemUser = true;
      group = "zennotes";
      home = cfg.dataDir;
      createHome = false;
    };
    users.groups.zennotes = { };

    sops.secrets.${cfg.authTokenSecret} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.vaultDir} 0750 zennotes zennotes -"
    ];

    systemd.services.zennotes = {
      description = "ZenNotes server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        ZENNOTES_BEHIND_TLS = "1";
        ZENNOTES_BIND = "127.0.0.1:${toString cfg.port}";
        ZENNOTES_CONFIG_PATH = "${cfg.dataDir}/server.json";
        ZENNOTES_DEFAULT_VAULT_PATH = cfg.vaultDir;
        ZENNOTES_BROWSE_ROOTS = cfg.vaultDir;
        ZENNOTES_ALLOWED_ORIGINS = "https://${cfg.subdomain}.${config.my.topology.domain}";
      };

      serviceConfig = {
        User = "zennotes";
        Group = "zennotes";
        StateDirectory = "zennotes";
        WorkingDirectory = cfg.dataDir;

        LoadCredential = "auth-token:${config.sops.secrets.${cfg.authTokenSecret}.path}";
        ExecStart = start;

        Restart = "always";
        RestartSec = 5;

        # The service only needs to read its vault, write its own state and
        # accept loopback HTTP. Everything else is denied.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        ReadWritePaths = [
          cfg.dataDir
          cfg.vaultDir
        ];
        UMask = "0077";
      };
    };

    my.contracts.provides.zennotes = {
      publications."web" = {
        endpoint = "web";
        scope = "public";
        auth = "none";
        subdomain = cfg.subdomain;
        # The application enforces its own bearer-token/session auth; API clients and the
        # desktop/TUI clients cannot complete a browser SSO redirect at the ingress.
        publicExempt = "ZenNotes enforces its own bearer-token and session authentication.";
      };

      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
      };

      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Notizen, Aufgaben und Wissen.";
          en = "Notes, tasks and knowledge.";
        };
        show = true;
        displayName = "ZenNotes";
        category = "Services";
        icon = "zennotes";
      };

      telemetry.probes."web-http" = {
        endpoint = "web";
        kind = "http";
      };

      storage.dataDirs = [ cfg.vaultDir ];
    };
  };
}
