{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.postgresql;
in
{
  options.my.features.services.postgresql = {
    enable = lib.mkEnableOption "Central PostgreSQL Database";
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_18;
      
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
  };
}
