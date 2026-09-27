{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.postgresql;

  # The cluster lives in a versioned data directory (`pg_upgrade` needs the old one to survive an
  # upgrade), and one binding feeds both the service and the backup exclusion, so the two cannot
  # disagree. It is computed from the package rather than read from `config.services.postgresql`:
  # that read would close a cycle, because `services.postgresql.ensureDatabases` is derived from the
  # consumed databases and the consumed databases are derived from the service contracts.
  dataDir = "/var/lib/postgresql/${pkgs.postgresql_18.psqlSchema}";
in
{
  options.my.features.services.postgresql = {
    enable = lib.mkEnableOption "Central PostgreSQL Database";
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_18;
      inherit dataDir;

      # Peer authentication for local socket connections
      authentication = pkgs.lib.mkOverride 10 ''
        #type database  DBuser  auth-method
        local all       all     peer
        host  all       all     127.0.0.1/32   scram-sha-256
        host  all       all     ::1/128        scram-sha-256
      '';
    };

    # Automatic Backups
    services.postgresqlBackup = {
      enable = true;
      location = "/var/lib/postgresql/backups";
      startAt = "*-*-* 02:00:00"; # Eine Stunde vor Restic
      backupAll = true;
    };

    my.contracts.provides.postgresql = {
      telemetry.probes."db-tcp".endpoint = "db";
      telemetry.probes."db-tcp".kind = "tcp";
      endpoints.db = {
        port = 5432;
        protocol = "tcp";
        applicationProtocol = "postgresql";
      };
      # The logical dump is the artifact that restores this service; the data directory is running state
      # a restore recreates from it, so it is declared out and derived from the module rather than copied
      # page by page. The dump directory stays in - it is the thing that has to survive.
      storage = {
        dataDirs = [ "/var/lib/postgresql/backups" ];
      };
      backup = {
        exclude = [ dataDir ];
      };
    };
  };
}
