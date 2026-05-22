{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.harmonia;

  cacheBcryptHash = "$2a$14$f1kz3UOVCCWlIno8SWjDKOfvMYmA.MPtjQ15.KA1R7mOT35UPyHmm";
in
{
  options.my.features.services.harmonia = {
    enable = lib.mkEnableOption "Harmonia Nix binary cache";
  };

  config = lib.mkIf cfg.enable {
    services.harmonia.cache = {
      enable = true;

      signKeyPaths = [ config.sops.secrets.harmonia-cache-key.path ];

      settings = {
        bind = "unix:/run/harmonia/socket";
        workers = 4;
        priority = 50;
      };
    };

    sops.secrets.harmonia-cache-key = { };

    systemd.services.harmonia.environment.RUST_LOG = "info";

    my.endpoints.harmonia = {
      host = config.networking.hostName;
      port = 5000;
      subdomain = "cache";
      auth = false;
      caddy.enable = false;
    };

    services.caddy.virtualHosts."cache.rls.ancoris.ovh" = {
      extraConfig = ''
        tls {
          alpn http/1.1
        }
        @upload {
          method PUT POST
        }
        basicauth @upload {
          ci ${cacheBcryptHash}
        }
        reverse_proxy unix//run/harmonia/socket {
          request_buffers 10MiB
        }
      '';
    };
  };
}
