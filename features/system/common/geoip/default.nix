{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.common.geoip;
in
{
  options.my.features.system.common.geoip = {
    enable = lib.mkEnableOption "MaxMind GeoIP Updates";
  };

  config = lib.mkIf cfg.enable {
    services.geoipupdate = {
      enable = true;
      settings = {
        EditionIDs = [ "GeoLite2-City" ];
      };
    };

    # geoipupdate expects GEOIPUPDATE_ACCOUNT_ID and GEOIPUPDATE_LICENSE_KEY in this file
    systemd.services.geoipupdate.serviceConfig.EnvironmentFile = [
      config.sops.secrets.geoip_env.path
    ];

    sops.secrets.geoip_env = { };
  };
}