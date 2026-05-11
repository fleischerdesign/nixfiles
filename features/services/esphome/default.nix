{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.esphome;
in
{
  options.my.features.services.esphome = {
    enable = lib.mkEnableOption "ESPHome Dashboard";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "esphome";
        description = "Subdomain to use";
      };
      auth = lib.mkEnableOption "Protect with Authentik (Forward Auth)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.esphome = {
      enable = true;
      port = 6052;
    };

    networking.firewall.allowedUDPPorts = [ 5353 ];

    # Register with Caddy Feature
    my.registry.esphome = {
      host = config.networking.hostName;
      port = 6052;
      subdomain = if cfg.expose.enable then cfg.expose.subdomain else null;
      auth = cfg.expose.auth;
    };
  };
}
