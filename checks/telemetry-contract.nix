{ pkgs, lib, ... }:
let
  fixture =
    values:
    (lib.evalModules {
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
then
  pkgs.runCommandLocal "telemetry-contract-check" { } ''
    echo "named observations and five independent negative controls passed" > "$out"
  ''
else
  throw "telemetry contract fixture failed: expected two probes of one endpoint and five distinct errors"
