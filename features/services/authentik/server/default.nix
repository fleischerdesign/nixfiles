{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.authentik.server;
  authentikPackage = pkgs.authentik;
in
{
  options.my.features.services.authentik.server = {
    enable = lib.mkEnableOption "Authentik Identity Provider (Server)";
  };

  config = lib.mkIf cfg.enable {
    
    # 1. User & Group
    users.users.authentik = {
      isSystemUser = true;
      group = "authentik";
      home = "/var/lib/authentik";
      createHome = true;
    };
    users.groups.authentik = {};

    # 2. Authentik Server Service
    systemd.services.authentik-server = {
      description = "Authentik Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "redis.service" ];
      
      serviceConfig = {
        ExecStart = "${lib.getExe authentikPackage} server";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        # Environment
        EnvironmentFile = config.sops.secrets.authentik_core_env.path;
        Environment = [
          "AUTHENTIK_REDIS__HOST=127.0.0.1"
          "AUTHENTIK_REDIS__PORT=6379"
          "AUTHENTIK_POSTGRESQL__HOST=/run/postgresql"
          "AUTHENTIK_POSTGRESQL__NAME=authentik"
          "AUTHENTIK_POSTGRESQL__USER=authentik"
          # Listen on localhost:9000 (Caddy proxies to this)
          "AUTHENTIK_LISTEN__HTTP=127.0.0.1:9000"
          "AUTHENTIK_LISTEN__METRICS=127.0.0.1:9300"
          "AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true"
          "AUTHENTIK_AVATARS=gravatar"
        ];
        Restart = "always";
      };
    };

    # 3. Authentik Worker Service
    systemd.services.authentik-worker = {
      description = "Authentik Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "redis.service" ];
      
      serviceConfig = {
        ExecStart = "${lib.getExe authentikPackage} worker";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        EnvironmentFile = config.sops.secrets.authentik_core_env.path;
        Environment = [
          "AUTHENTIK_REDIS__HOST=127.0.0.1"
          "AUTHENTIK_REDIS__PORT=6379"
          "AUTHENTIK_POSTGRESQL__HOST=/run/postgresql"
          "AUTHENTIK_POSTGRESQL__NAME=authentik"
          "AUTHENTIK_POSTGRESQL__USER=authentik"
        ];
        Restart = "always";
      };
    };

    # 4. Database Setup (Ensure DB exists)
    services.postgresql = {
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        {
          name = "authentik";
          ensureDBOwnership = true;
        }
      ];
    };

    # Reverse Proxy
    my.features.services.caddy.exposedServices = {
      "authentik" = {
        port = 9000;
        subdomain = "authentik";
      };
    };

    # 6. Secrets
    sops.secrets.authentik_core_env = {
      owner = "authentik";
    };
  };
}