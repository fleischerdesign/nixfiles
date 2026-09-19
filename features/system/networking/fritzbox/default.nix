# features/system/networking/fritzbox/default.nix
# Declarative FRITZ!Box Router GitOps Engine (TR-064 API / Agentless Architecture).
# Reconciles DNS, DHCP, and router settings idempotently from `my.topology`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.fritzbox;
  topology = config.my.topology;
  routerHost = topology.hosts.hom-rt-01 or null;
  serverHost = topology.hosts.hom-srv-01 or null;

  # Submodule for declarative port forwarding rules
  portForwardSubmodule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Description or identifier of the port forward rule";
      };
      protocol = lib.mkOption {
        type = lib.types.enum [
          "TCP"
          "UDP"
        ];
        default = "TCP";
        description = "Transport protocol";
      };
      externalPort = lib.mkOption {
        type = lib.types.port;
        description = "External WAN listening port";
      };
      internalClient = lib.mkOption {
        type = lib.types.str;
        description = "Internal target IP address";
      };
      internalPort = lib.mkOption {
        type = lib.types.port;
        description = "Internal destination port";
      };
    };
  };

  # Render desired state configuration as JSON derivation
  desiredStateJson = pkgs.writeText "fritzbox-desired-state.json" (
    builtins.toJSON {
      host = cfg.host;
      user = cfg.user;
      passwordSecret = cfg.passwordSecret;
      settings = {
        dns = {
          primary = cfg.settings.dns.primary;
          fallback = cfg.settings.dns.fallback;
        };
        dhcp = {
          enable = cfg.settings.dhcp.enable;
        };
        portForwardings = cfg.settings.portForwardings;
      };
    }
  );

  # Hermetic Python interpreter with fritzconnection
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.fritzconnection
  ]);

  # Executable wrapper
  syncScript = pkgs.writeShellScriptBin "fritzbox-sync" ''
    exec ${pythonEnv}/bin/python3 ${./sync.py} --spec ${desiredStateJson} "$@"
  '';
in
{
  options.my.features.system.networking.fritzbox = {
    enable = lib.mkEnableOption "Declarative FRITZ!Box Router GitOps Engine (TR-064)";

    host = lib.mkOption {
      type = lib.types.str;
      default =
        let
          migrationAddresses = if routerHost == null then [ ] else routerHost.migration.addresses;
        in
        if migrationAddresses != [ ] then
          # Still on the old network: reach it where it currently answers.
          lib.head (lib.splitString "/" (lib.head migrationAddresses))
        else if routerHost != null && routerHost.ipv4 != null then
          routerHost.ipv4
        else
          "10.10.10.1";
      description = ''
        TR-064 reachable address of the FRITZ!Box. While the topology declares a `migration`
        address the box is reached there (it has not moved yet); `ipv4` stays the target address
        that the reconciler will set once it can write the LAN interface.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "TR-064 API username configured on the FRITZ!Box";
    };

    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "services/fritzbox/password";
      description = "SOPS secret identifier containing the FRITZ!Box management password";
    };

    settings = {
      dns = {
        primary = lib.mkOption {
          type = lib.types.str;
          default = if serverHost != null && serverHost.ipv4 != null then serverHost.ipv4 else "10.10.10.10";
          description = "Primary DNS server handed out or upstream (hom-srv-01 Blocky DNS)";
        };

        fallback = lib.mkOption {
          type = lib.types.str;
          default = "1.1.1.1";
          description = "Fallback upstream DNS resolver";
        };
      };

      dhcp = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether DHCP is enabled on the router (false offloads DHCP to hom-srv-01 Kea)";
        };
      };

      portForwardings = lib.mkOption {
        type = lib.types.listOf portForwardSubmodule;
        default = [ ];
        description = "Declarative list of WAN port forwardings (default empty for Zero Open Ports)";
      };
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = syncScript;
      readOnly = true;
      description = "The compiled fritzbox-sync executable package";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
