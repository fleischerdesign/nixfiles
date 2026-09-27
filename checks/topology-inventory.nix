{ pkgs, lib, ... }:
let
  fixture =
    values:
    (lib.evalModules {
      specialArgs = {
        inherit lib;
        cidrLib = import ../lib/cidr.nix { inherit lib; };
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
        }
        ../features/system/networking/topology/nixos.nix
        { my.topology = values; }
      ];
    }).config;

  # A second inventory through the untouched schema: two zones sharing one trust level, and an
  # extension module adding a host without discarding the others.
  base = {
    subnets = {
      corp = {
        cidr = "10.10.20.0/24";
        trustLevel = "corp";
      };
      lab = {
        cidr = "10.10.30.0/24";
        trustLevel = "corp";
      };
    };
    hosts = {
      wrk-01 = {
        zone = "corp";
        ipv4 = "10.10.20.10";
        wireguardIpv4 = "10.10.100.20";
      };
    };
    devices = {
      prn-01 = {
        zone = "lab";
        ipv4 = "10.10.30.19";
      };
    };
  };
  valid = fixture base;
  verdicts = values: lib.filter (entry: !entry.assertion) (fixture values).assertions;
  messages = values: map (entry: entry.message) (verdicts values);
  break = values: lib.recursiveUpdate base values;

  badZone = messages (break {
    hosts.wrk-01.zone = "nowhere";
  });
  badAddress = messages (break {
    hosts.wrk-01.ipv4 = "10.10.20.999";
  });
  duplicateAddress = messages (break {
    devices.prn-01.ipv4 = "10.10.20.10";
  });
  outsideSubnet = messages (break {
    devices.prn-01.ipv4 = "10.10.20.99";
  });
  badCidr = messages (break {
    subnets.corp.cidr = "10.10.20.0/33";
  });
  contains = text: strings: lib.any (lib.hasInfix text) strings;
in
if
  verdicts base == [ ]
  # Two zones share one trust level, and both resolve through it. Devices are not sources:
  # only hosts answer for a trust level.
  &&
    valid.my.topology.sourcesByTrust.corp == [
      "10.10.20.10/32"
      "10.10.100.20/32"
    ]
  && valid.my.topology.announcedZones == [ "lab" ]
  && contains "unknown zone" badZone
  && contains "malformed IPv4" badAddress
  && contains "claimed more than once" duplicateAddress
  && contains "outside their zone" outsideSubnet
  && contains "malformed subnet CIDRs" badCidr
then
  pkgs.runCommandLocal "topology-inventory-check" { } ''
    echo "second inventory, shared trust level and five independent negative controls passed" > "$out"
  ''
else
  throw "topology inventory fixture failed: expected shared trust levels and five distinct errors"
