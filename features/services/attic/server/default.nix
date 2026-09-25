{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.attic.server;

  # Single source for the cache's FQDN: flat and plane-derived (Naming spec §3).
in
{
  options.my.features.services.attic.server = {
    enable = lib.mkEnableOption "Attic Nix binary cache server";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."infra/attic/server_token_secret" = { };

    sops.templates.atticd_env = {
      content = ''
        ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=${config.sops.placeholder."infra/attic/server_token_secret"}
      '';
    };

    services.atticd = {
      enable = true;
      mode = "monolithic";
      environmentFile = config.sops.templates.atticd_env.path;
      settings = {
        listen = "0.0.0.0:8080";
        allowed-hosts = [ config.my.contracts.provides.attic.endpoints.web.canonicalDomain ];
        api-endpoint = "https://${config.my.contracts.provides.attic.endpoints.web.canonicalDomain}/";
        chunking = {
          nar-size-threshold = 16 * 1024 * 1024;
          min-size = 256 * 1024;
          avg-size = 1024 * 1024;
          max-size = 4 * 1024 * 1024;
        };
        database = {
          url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
          max-connections = 64;
        };
        storage = {
          type = "local";
          path = "/var/lib/atticd/storage";
        };
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "90 days";
        };
      };
    };

    # The `cache` endpoint is the single source of truth: Caddy's contract
    # projection derives the reverse proxy and Cloudflare derives the DNS record.
    my.contracts.provides.attic.endpoints.web = {
      port = 8080;
      protocol = "tcp";
      scope = "public";
      auth = "none";
      subdomain = "cache";
      publicExempt = "bearer-token authentication of its own; nix substituters cannot perform a browser SSO redirect";
      # The ingress terminates TLS and proxies over the WireGuard mesh (Naming spec §5, invariant
      # I10), so the listener must be reachable there; the firewall confines it to wg0.
      directAccess = {
        enable = true;
        protocol = "tcp";
        interface = "wireguard";
      };
      # Streaming binary cache: do not buffer. Declared as a proxy option (not as raw
      # Caddyfile) so the upstream target stays projected onto the ingress (Naming spec §0.3).
      proxyOptions = "flush_interval -1";

      # High-frequency reads on narinfo and non-static binary cache objects are legitimate behavior
      # for nix substituters and CI/CD runners; exempt them from web crawl / scan detectors.
      crowdsec.exemptScenarios = [
        "crowdsecurity/http-crawl-non_statics"
        "crowdsecurity/http-probing"
      ];
    };
  };
}
