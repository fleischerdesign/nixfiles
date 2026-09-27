# features/services/monitoring/pipeline.nix
# Centralized monitoring pipeline orchestrator.
# No hub/cross-component knowledge scattered across hosts — one module owns it.
{
  config,
  lib,
  fleetConfigs,
  ...
}:

let
  cfg = config.my.features.services.monitoring.pipeline;
  topology = config.my.topology;

  # The hub as this host reaches it: the LAN address while both are at home, otherwise the overlay
  # address (lib/addresses.nix states the rule once, for every consumer).
  addresses = import ../../../../lib/addresses.nix { inherit lib; };
  serviceAddress =
    peer:
    addresses.serviceAddress {
      inherit topology;
      consumer = topology.hosts.${config.networking.hostName} or null;
      inherit peer;
    };
in
{
  options.my.features.services.monitoring.pipeline = {
    enable = lib.mkEnableOption "Centralized monitoring pipeline (orchestrates prometheus, loki, grafana, alloy, exporters)";

    role = lib.mkOption {
      type = lib.types.enum [
        "full"
        "collector"
      ];
      default = "collector";
      description = ''
        full: hub — enables prometheus + loki + grafana + all agents
        collector: spoke — enables alloy + node-exporter + blackbox-exporter
      '';
    };

    hub = lib.mkOption {
      type = lib.types.str;
      default = fleetConfigs.uniqueHost {
        systems = fleetConfigs.systems config;
        matches = hostCfg: (hostCfg.my.features.services.monitoring.pipeline.role or "collector") == "full";
        role = "monitoring hub";
      };
      description = "Hostname of the monitoring hub. Derived as the single host with the full role; an explicit override must name a full-role host. Used to configure alloy's loki endpoint on collectors.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              let
                hubCfg = (fleetConfigs.systems config).${cfg.hub}.config or null;
              in
              hubCfg != null && (hubCfg.my.features.services.monitoring.pipeline.role or "collector") == "full";
            message = "monitoring pipeline: hub '${cfg.hub}' on ${config.networking.hostName} is not a host with the full role";
          }
        ];
      }
      # Base: all roles get agents
      {
        my.features.services.monitoring = {
          alloy.enable = lib.mkDefault true;
          node-exporter.enable = lib.mkDefault true;
          blackbox-exporter.enable = lib.mkDefault true;
        };
      }

      # Full role: additionally enable hub components
      (lib.mkIf (cfg.role == "full") {
        my.features.services.monitoring = {
          prometheus.enable = lib.mkDefault true;
          loki.enable = lib.mkDefault true;
          grafana.enable = lib.mkDefault true;
        };
      })

      # Configure alloy's loki endpoint. An unknown hub fails loudly: shipping logs to
      # loopback by accident would discard every log line on the floor.
      {
        my.features.services.monitoring.alloy.lokiHost = lib.mkDefault (
          if cfg.role == "full" then
            "127.0.0.1"
          else
            let
              hubTopology = topology.hosts.${cfg.hub} or null;
            in
            if hubTopology != null && hubTopology.wireguardIpv4 != null then
              serviceAddress hubTopology
            else
              throw "monitoring pipeline: hub '${cfg.hub}' on ${config.networking.hostName} has no usable address in the inventory"
        );
      }
    ]
  );
}
