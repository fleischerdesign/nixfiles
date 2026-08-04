{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.attic.server;
in
{
  options.my.features.services.attic.server = {
    enable = lib.mkEnableOption "Attic Nix binary cache server";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "cache.rls.ancoris.ovh";
      description = "Full domain name for atticd.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.atticd_token_secret = { };

    sops.templates.atticd_env = {
      content = ''
        ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=${config.sops.placeholder.atticd_token_secret}
      '';
    };

    services.atticd = {
      enable = true;
      mode = "monolithic";
      environmentFile = config.sops.templates.atticd_env.path;
      settings = {
        listen = "127.0.0.1:8080";
        allowed-hosts = [ cfg.domain ];
        api-endpoint = "https://${cfg.domain}/";
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

    services.caddy.virtualHosts."${cfg.domain}" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8080 {
          flush_interval -1
        }
      '';
    };
  };
}
