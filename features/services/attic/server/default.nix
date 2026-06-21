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
        database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
        storage = {
          type = "local";
          path = "/var/lib/atticd/storage";
        };
      };
    };

    services.caddy.virtualHosts."${cfg.domain}" = {
      extraConfig = ''
        tls {
          alpn http/1.1
        }
        reverse_proxy 127.0.0.1:8080 {
          request_buffers 10MiB
        }
      '';
    };
  };
}
