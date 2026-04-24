{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.navidrome;
in
{
  options.my.features.services.navidrome = {
    enable = lib.mkEnableOption "Navidrome Music Server";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "navidrome"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure media group exists
    users.groups.media = { };

    users.users.navidrome = {
      isSystemUser = true;
      group = "navidrome";
      extraGroups = [ "media" ];
    };
    users.groups.navidrome = { };

    services.navidrome = {
      enable = true;
      settings = {
        MusicFolder = "/data/storage/music";
        Address = "0.0.0.0";
        Port = 4533;
        # Forward Auth via Authentik
        "ExtAuth.TrustedSources" = "127.0.0.1/32";
        "ExtAuth.UserHeader" = "X-Authentik-Username";
        "ExtAuth.LogoutURL" = "https://${cfg.expose.subdomain}.${config.my.features.services.caddy.baseDomain}/outpost.goauthentik.io/sign_out";
      };
    };

    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "navidrome" = {
        port = 4533;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}