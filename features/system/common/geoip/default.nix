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
        AccountID = 1180469;
        LicenseKey = config.sops.secrets.geoip_license_key.path;
        EditionIDs = [ "GeoLite2-City" ];
      };
    };

    sops.secrets.geoip_license_key = { };
  };
}
