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

      settings = {
        bind = "127.0.0.1:5000";
        workers = 4;
        priority = 50;
      };
    };

    my.endpoints.harmonia = {
      host = config.networking.hostName;
      port = 5000;
      subdomain = "cache";
      auth = false;
      caddy.enable = false;
    };

    services.caddy.virtualHosts."cache.rls.ancoris.ovh" = {
      extraConfig = ''
        @upload {
          method PUT POST
        }
        basicauth @upload {
          ci ${cacheBcryptHash}
        }
        reverse_proxy 127.0.0.1:5000
      '';
    };
  };
}
