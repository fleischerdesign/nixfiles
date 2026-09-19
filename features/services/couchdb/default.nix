{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.couchdb;
in
{
  options.my.features.services.couchdb = {
    enable = lib.mkEnableOption "CouchDB Server";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "couchdb.${config.my.topology.domain}";
      description = "Full domain name for CouchDB (derived; Naming spec §3).";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. CouchDB Service
    services.couchdb = {
      enable = true;
      package = pkgs.couchdb3;
      bindAddress = "127.0.0.1";
      port = 5984;

      # Inject config via templates (passwords)
      extraConfigFiles = [ config.sops.templates."couchdb_admin.ini".path ];

      # CORS Settings for Obsidian
      extraConfig = {
        httpd = {
          enable_cors = true;
        };
        cors = {
          origins = "*";
          credentials = true;
          methods = "GET, PUT, POST, HEAD, DELETE";
          headers = "accept, authorization, content-type, origin, referer";
        };
      };
    };

    # 2. SOPS Secrets
    sops.secrets."services/storage/couchdb_admin_password" = {
      owner = "couchdb";
    };
    sops.secrets."services/storage/couchdb_obsidian_password" = {
      owner = "couchdb";
    };

    # 3. Generate the admin config file (CouchDB 3.x uses [admins] section)
    sops.templates."couchdb_admin.ini" = {
      owner = "couchdb";
      content = ''
        [admins]
        admin = ${config.sops.placeholder."services/storage/couchdb_admin_password"}
        obsidian = ${config.sops.placeholder."services/storage/couchdb_obsidian_password"}
      '';
    };

    # 4. Service Contract for Ingress & Storage
    my.contracts.provides.couchdb = {
      endpoints.web = {
        port = 5984;
        protocol = "tcp";
        scope = "public";
        auth = "none";
        subdomain = "couchdb";
      };
      storage = {
        stateDirs = [ "/var/lib/couchdb" ];
      };
    };
  };
}
