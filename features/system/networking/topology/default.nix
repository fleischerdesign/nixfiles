# features/system/networking/topology/default.nix
# Zentrale Konfiguration für Netzwerk-Topologie und Host-IP-Zuweisungen
{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.my.features.system.networking.topology = {
    enable = lib.mkEnableOption "Zentrale Netzwerk-Topologie-Konfiguration";

    mackaye = {
      tailscaleIp = lib.mkOption {
        type = lib.types.str;
        default = "100.120.39.68";
        description = "Tailscale IP für Host mackaye";
      };
      localIp = lib.mkOption {
        type = lib.types.str;
        default = "192.168.1.10";
        description = "Lokale IP für Host mackaye";
      };
    };

    strummer = {
      tailscaleIp = lib.mkOption {
        type = lib.types.str;
        default = "100.125.253.108";
        description = "Tailscale IP für Host strummer";
      };
      localIp = lib.mkOption {
        type = lib.types.str;
        default = "192.168.178.27";
        description = "Lokale IP für Host strummer";
      };
    };
  };

  config = lib.mkIf config.my.features.system.networking.topology.enable {
    # Exportiere IPs für andere Module
    # Zugriff über config.my.features.system.networking.topology.mackaye.tailscaleIp
    exports = {
      mackaye = {
        tailscaleIp = config.my.features.system.networking.topology.mackaye.tailscaleIp;
        localIp = config.my.features.system.networking.topology.mackaye.localIp;
      };
      strummer = {
        tailscaleIp = config.my.features.system.networking.topology.strummer.tailscaleIp;
        localIp = config.my.features.system.networking.topology.strummer.localIp;
      };
    };
  };
}
