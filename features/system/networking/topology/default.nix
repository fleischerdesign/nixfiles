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
    enable = lib.mkEnableOption "Centralized network topology configuration";

    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            tailscaleIp = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Tailscale IP of the host";
            };
            localIp = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Local IP of the host";
            };
            domain = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Primary domain of the host";
            };
            hostType = lib.mkOption {
              type = lib.types.enum [
                "server"
                "client"
              ];
              default = "client";
              description = "Host type — clients are excluded from server-targeted probes";
            };
          };
        }
      );
      default = { };
      description = "Definition of all known hosts in the network";
    };
  };

  config = lib.mkIf config.my.features.system.networking.topology.enable {
    my.features.system.networking.topology.hosts = {
      mackaye = {
        tailscaleIp = "100.120.39.68";
        localIp = "173.249.22.211";
        domain = "mky.ancoris.ovh";
        hostType = "server";
      };

      strummer = {
        tailscaleIp = "100.125.253.108";
        localIp = "192.168.178.27";
        domain = "fls.ancoris.ovh";
        hostType = "server";
      };

      jello = {
        tailscaleIp = "100.88.135.75";
        localIp = "192.168.178.30";
        domain = "jlo.ancoris.ovh";
      };

      yorke = {
        tailscaleIp = "100.107.168.30";
        localIp = "192.168.178.179";
        domain = "yrk.ancoris.ovh";
      };
    };
  };
}
