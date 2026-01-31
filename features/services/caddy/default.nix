{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.caddy;
in
{
  options.my.features.services.caddy.enable = lib.mkEnableOption "Caddy Web Server";

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
    networking.firewall.allowedUDPPorts = [ 443 ]; # QUIC / HTTP/3
  };
}
