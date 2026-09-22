# contracts/telemetry/default.nix
# Declarative Telemetry & Observability Contract Specification.
# Services declare Prometheus scrape targets, structured logs/journal filters,
# and alert specifications orthogonally from HTTP/TCP endpoint routing.
{
  lib,
  ...
}:

let
  telemetryContractSubmodule = lib.types.submodule {
    options = {
      metrics = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether Prometheus should scrape metrics from this service";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 80;
          description = "Port to scrape Prometheus metrics from";
        };

        path = lib.mkOption {
          type = lib.types.str;
          default = "/metrics";
          description = "Path to Prometheus metrics endpoint";
        };

        scheme = lib.mkOption {
          type = lib.types.enum [
            "http"
            "https"
          ];
          default = "http";
          description = "Protocol scheme for metric scraping";
        };

        interval = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional scrape interval override (e.g. '15s', '1m')";
        };
      };

      logs = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether Loki / Alloy should collect and label logs for this service";
        };

        systemdUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Systemd unit names to associate with service log streams in Loki";
        };

        extraLabels = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Static labels to attach to this service's log streams";
        };
      };

      alerts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Alert rule name";
              };
              expr = lib.mkOption {
                type = lib.types.str;
                description = "PromQL expression triggering the alert";
              };
              duration = lib.mkOption {
                type = lib.types.str;
                default = "5m";
                description = "Duration the expression must be true before firing";
              };
              severity = lib.mkOption {
                type = lib.types.enum [
                  "warning"
                  "critical"
                  "info"
                ];
                default = "warning";
                description = "Alert severity level";
              };
              summary = lib.mkOption {
                type = lib.types.str;
                description = "Summary message for human operators / notification channels";
              };
            };
          }
        );
        default = [ ];
        description = "Service-level declarative Prometheus alerting rules";
      };
    };
  };
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.telemetry = lib.mkOption {
          type = telemetryContractSubmodule;
          default = { };
          description = "Observability, metrics scraping, log shipping, and alerting declarations";
        };
      }
    );
  };
}
