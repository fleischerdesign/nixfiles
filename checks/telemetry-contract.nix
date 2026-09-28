{ pkgs, lib, ... }:
let
  fixture =
    values:
    (lib.evalModules {
      specialArgs = {
      };
      modules = [
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  assertion = lib.mkOption { type = lib.types.bool; };
                  message = lib.mkOption { type = lib.types.str; };
                };
              }
            );
            default = [ ];
          };
          options.my.contracts.provides = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.endpoints = lib.mkOption {
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options = {
                        applicationProtocol = lib.mkOption { type = lib.types.str; };
                        protocol = lib.mkOption { type = lib.types.str; };
                      };
                    }
                  );
                  default = { };
                };
              }
            );
          };
        }
        ../contracts/telemetry/nixos.nix
        { my.contracts.provides.example = values; }
      ];
    }).config;
  endpoints = {
    web = {
      applicationProtocol = "http";
      protocol = "tcp";
    };
    ssh = {
      applicationProtocol = "ssh";
      protocol = "tcp";
    };
    transport = {
      applicationProtocol = "other";
      protocol = "udp";
    };
  };
  failures =
    value: map (entry: entry.message) (lib.filter (entry: !entry.assertion) (fixture value).assertions);
  valid = {
    inherit endpoints;
    telemetry.probes = {
      ready = {
        endpoint = "web";
        kind = "http";
        path = "/ready";
      };
      alive = {
        endpoint = "web";
        kind = "http";
        path = "/alive";
      };
      ssh = {
        endpoint = "ssh";
        kind = "tcp";
      };
    };
    telemetry.scrapes.metrics.endpoint = "web";
  };
  unknown = failures {
    inherit endpoints;
    telemetry.probes.bad = {
      endpoint = "missing";
      kind = "http";
    };
  };
  wrongHttp = failures {
    inherit endpoints;
    telemetry.probes.bad = {
      endpoint = "ssh";
      kind = "http";
    };
  };
  wrongTcp = failures {
    inherit endpoints;
    telemetry.probes.bad = {
      endpoint = "transport";
      kind = "tcp";
    };
  };
  wrongScrape = failures {
    inherit endpoints;
    telemetry.scrapes.bad.endpoint = "ssh";
  };
  wrongPath = failures {
    inherit endpoints;
    telemetry.probes.bad = {
      endpoint = "web";
      kind = "http";
      path = "relative";
    };
  };
  contains = text: strings: lib.any (lib.hasInfix text) strings;

  monitoredHost = path: {
    config = {
      my.features.services.monitoring.blackbox-exporter.enable = true;
      my.contracts.provides.demo = {
        endpoints.web = {
          port = 8080;
          localUrl = "http://127.0.0.1:8080";
        };
        publications = { };
        telemetry = {
          probes = {
            ready = {
              endpoint = "web";
              kind = "http";
              path = "/ready";
            };
            live = {
              endpoint = "web";
              kind = "http";
              path = "/live";
            };
          };
          scrapes.metrics = {
            endpoint = "web";
            jobName = "demo";
            inherit path;
          };
        };
      };
    };
  };
  monitoringModule = import ../features/services/monitoring/prometheus/nixos.nix {
    inherit lib;
    fleetConfigs = {
      systems = _: {
        a = monitoredHost "/metrics-a";
        b = monitoredHost "/metrics-b";
      };
      providesOf = host: host.config.my.contracts.provides;
    };
    config = {
      networking.hostName = "a";
      my.features.services.monitoring.prometheus.enable = true;
      my.topology = {
        hosts = {
          a = {
            ipv4 = null;
            wireguardIpv4 = "192.0.2.1";
            zone = "mesh";
          };
          b = {
            ipv4 = null;
            wireguardIpv4 = "192.0.2.2";
            zone = "mesh";
          };
        };
        lanZones = [ ];
        devices = { };
      };
    };
  };
  renderedJobs = monitoringModule.config.content.services.prometheus.scrapeConfigs;
  renderedScrape = lib.findFirst (job: job.job_name == "demo") null renderedJobs;
  renderedProbes = lib.findFirst (job: job.job_name == "blackbox-http-local") null renderedJobs;
  renderedPaths = map (target: target.labels.metrics_path) renderedScrape.static_configs;
  renderedObservations = map (target: target.labels.observation) renderedProbes.static_configs;
in
if
  failures valid == [ ]
  &&
    builtins.length (builtins.attrNames (fixture valid).my.contracts.provides.example.telemetry.probes)
    == 3
  && contains "unknown endpoint 'missing'" unknown
  && contains "HTTP observation requires an HTTP endpoint" wrongHttp
  && contains "TCP probe requires a TCP endpoint" wrongTcp
  && contains "HTTP observation requires an HTTP endpoint" wrongScrape
  && contains "path must start with '/'" wrongPath
  &&
    renderedPaths == [
      "/metrics-a"
      "/metrics-b"
    ]
  &&
    renderedObservations == [
      "live"
      "ready"
      "live"
      "ready"
    ]
  && lib.any (
    rule: rule.target_label == "__metrics_path__" && rule.source_labels == [ "metrics_path" ]
  ) renderedScrape.relabel_configs
then
  pkgs.runCommandLocal "telemetry-contract-check" { } ''
    echo "named telemetry, consumer-specific probe identities and per-target scrape relabeling passed" > "$out"
  ''
else
  throw "telemetry fixture failed: expected distinct observations and per-target scrape paths to reach Prometheus"
