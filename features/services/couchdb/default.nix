{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.couchdb;
in
{
  options.my.features.services.couchdb = {
    enable = lib.mkEnableOption "CouchDB Server";
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
    sops.secrets.couchdb_admin_password = { owner = "couchdb"; };
    sops.secrets.couchdb_obsidian_password = { owner = "couchdb"; };

    # 3. Generate the admin config file (CouchDB 3.x uses [admins] section)
    sops.templates."couchdb_admin.ini" = {
      owner = "couchdb";
      content = ''
        [admins]
        admin = ${config.sops.placeholder.couchdb_admin_password}
        obsidian = ${config.sops.placeholder.couchdb_obsidian_password}
      '';
    };

    # 4. Reverse Proxy via Caddy
    my.features.services.caddy.exposedServices = {
      "couchdb" = {
        port = 5984;
        fullDomain = "couchdb.mky.ancoris.ovh";
      };
    };
  };
}