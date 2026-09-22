{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.obsidian-livesync;
in
{
  options.my.features.services.obsidian-livesync = {
    enable = lib.mkEnableOption "Obsidian LiveSync Server (CouchDB Backend)";

  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.couchdb" ] config)

      {
        my.features.services.couchdb.enable = true;

        services.couchdb = {
          extraConfig = {
            couchdb = {
              max_document_size = 4294967296;
            };
            chttpd = {
              max_http_request_size = 4294967296;
              enable_cors = true;
            };
            cors = {
              origins = "app://obsidian.md,capacitor://localhost,http://localhost,https://${config.my.contracts.provides.obsidian-livesync.endpoints.web.canonicalDomain}";
              credentials = true;
              methods = "GET, PUT, POST, HEAD, DELETE";
              headers = "accept, authorization, content-type, origin, referer";
            };
          };
        };

        my.contracts.provides.obsidian-livesync = {
          endpoints.web = {
            port = 5984;
            protocol = "tcp";
            scope = "public";
            auth = "none";
            subdomain = "livesync";
            publicExempt = "delegates authentication to CouchDB; LiveSync clients cannot perform a browser SSO redirect";
            dashboard = {
              description = {
                de = "Synchronisation der Obsidian-Notizen.";
                en = "Sync for Obsidian notes.";
              };
              show = true;
              displayName = "Obsidian LiveSync";
              category = "Productivity";
              icon = "obsidian";
            };
          };
        };
      }
    ]
  );
}
