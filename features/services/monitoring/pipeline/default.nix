# features/services/monitoring/pipeline.nix
# Centralized monitoring pipeline orchestrator.
# No hub/cross-component knowledge scattered across hosts — one module owns it.
{
  config,
  lib,
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
      default = "cld-edge-01";
      description = "Hostname of the monitoring hub. Used to configure alloy's loki endpoint on collectors.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
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

      # Configure alloy's loki endpoint
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
              "127.0.0.1"
        );
      }
    ]
  );
}
