# features/system/networking/topology/default.nix
# Zentrale Konfiguration für Netzwerk-Topologie und Host-IP-Zuweisungen
{
  config,
  lib,
  ...
}:

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
            gateway = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Default gateway IP of the host";
            };
          };
        }
      );
      default = { };
      description = "Definition of all known hosts in the network";
    };
    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.178.0/24"
        "100.64.0.0/10"
      ];
      description = "Trusted IP subnets (LAN and Tailscale CGNAT range) for internal access and IPS whitelisting.";
    };
  };

  config = lib.mkIf config.my.features.system.networking.topology.enable {
    my.features.system.networking.topology.hosts = {
      mackaye = {
        tailscaleIp = "100.120.39.68";
        localIp = "173.249.22.211";
        domain = "mky.ancoris.ovh";
        hostType = "server";
        gateway = "173.249.22.1";
      };

      rollins = {
        tailscaleIp = "100.126.5.72";
        localIp = "37.114.55.91";
        domain = "rls.ancoris.ovh";
        hostType = "server";
        gateway = "37.114.55.1";
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
