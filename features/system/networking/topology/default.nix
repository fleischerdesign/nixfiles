# features/system/networking/topology/default.nix
# Zentrale Konfiguration für Netzwerk-Topologie und Host-IP-Zuweisungen
{
  config,
  lib,
  ...
}:

let
  hostSubmodule = lib.types.submodule {
    options = {
      tailscaleIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Tailscale IP des Hosts";
      };
      localIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Lokale IP des Hosts";
      };
    };
  };
in
{
  options.my.features.system.networking.topology = {
    enable = lib.mkEnableOption "Zentrale Netzwerk-Topologie-Konfiguration";

    hosts = lib.mkOption {
      type = lib.types.attrsOf hostSubmodule;
      default = { };
      description = "Definition aller bekannten Hosts im Netzwerk";
    };
  };

  config = lib.mkIf config.my.features.system.networking.topology.enable {
    my.features.system.networking.topology.hosts = {
      mackaye = {
        tailscaleIp = "100.120.39.68";
        localIp = "192.168.1.10";
      };

      strummer = {
        tailscaleIp = "100.125.253.108";
        localIp = "192.168.178.27";
      };

      jello = { };
      yorke = { };
    };
  };
}