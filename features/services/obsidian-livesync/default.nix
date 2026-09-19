{
  config,
  options,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.obsidian-livesync;
  caddyOpt = options.my.features.services.caddy.baseDomain or null;
  caddyBaseDomain =
    if caddyOpt != null && caddyOpt.isDefined then
      config.my.features.services.caddy.baseDomain
    else
      "edge.${config.my.topology.domain}";
in
{
  options.my.features.services.obsidian-livesync = {
    enable = lib.mkEnableOption "Obsidian LiveSync Server (CouchDB Backend)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "livesync.${caddyBaseDomain}";
      description = "Full domain name for Obsidian LiveSync endpoint.";
    };
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
              origins = "app://obsidian.md,capacitor://localhost,http://localhost,https://${cfg.domain}";
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
            dashboard = {
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
