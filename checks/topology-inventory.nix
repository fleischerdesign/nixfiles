{
  pkgs,
  lib,
  self,
  ...
}:
let
  cidrLib = import ../lib/cidr.nix { inherit lib; };
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
        ../contracts/topology/nixos.nix
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
  badHostAddress = messages (break {
    hosts.wrk-01.ipv4 = "198.51.100.10";
  });
  overlappingZones = messages (
    lib.recursiveUpdate base {
      subnets.overlap = {
        cidr = "10.10.20.128/25";
        trustLevel = "iot";
      };
    }
  );
  gatewayCollision = messages (
    lib.recursiveUpdate base {
      subnets.corp.gateway = "10.10.20.10";
      hosts.wrk-01.ipv4 = "10.10.20.10";
    }
  );
  declaredGatewayOwner = lib.recursiveUpdate base {
    subnets.corp.gateway = "10.10.20.10";
    subnets.corp.gatewayHost = "wrk-01";
    hosts.wrk-01.ipv4 = "10.10.20.10";
  };
  v6Base = lib.recursiveUpdate base {
    subnets.mesh-v6 = {
      cidr = "fd10:1000:100::/64";
      trustLevel = "mesh";
    };
    hosts.wrk-01.wireguardIpv6 = "fd10:1000:100::20";
  };
  malformedV6 = messages (
    lib.recursiveUpdate v6Base { hosts.wrk-01.wireguardIpv6 = "not-an-address"; }
  );
  duplicateV6 = messages (
    lib.recursiveUpdate v6Base {
      hosts.other = {
        zone = "corp";
        wireguardIpv6 = "fd10:1000:100:0:0:0:0:20";
      };
    }
  );
  outsideV6 = messages (
    lib.recursiveUpdate v6Base { hosts.wrk-01.wireguardIpv6 = "fd10:1000:101::20"; }
  );
  overlappingV6Zones = messages (
    lib.recursiveUpdate v6Base {
      subnets.mesh-v6-overlap = {
        cidr = "fd10:1000:100::/80";
        trustLevel = "mesh";
      };
    }
  );
  guestZone = fixture (
    base
    // {
      subnets = base.subnets // {
        visitors = {
          cidr = "192.0.2.0/24";
          trustLevel = "guest";
        };
      };
      devices = base.devices // {
        visitor-device = {
          zone = "visitors";
          ipv4 = "192.0.2.20";
        };
      };
    }
  );
  relocatedSiteRoles = self.nixosConfigurations.hom-srv-01.extendModules {
    modules = [
      {
        my.topology.upstreamRouter = lib.mkForce "hom-ap-01";
        my.topology.accessPoint = lib.mkForce "hom-rt-01";
        my.topology.primaryWireguardHub = lib.mkForce "cld-ops-01";
      }
    ];
  };
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
  && contains "outside their zone's subnet" badHostAddress
  && contains "overlapping subnets" overlappingZones
  && contains "gateway address conflicts" gatewayCollision
  && !(contains "gateway address conflicts" (verdicts declaredGatewayOwner))
  && contains "malformed IPv6" malformedV6
  && contains "IPv6 overlay addresses claimed more than once" duplicateV6
  && contains "outside all declared IPv6 subnets" outsideV6
  && contains "overlapping subnets" overlappingV6Zones
  && guestZone.my.topology.announcedZones == [ "lab" ]
  && relocatedSiteRoles.config.my.features.system.networking.fritzbox.host == "10.10.10.20"
  && relocatedSiteRoles.config.my.features.system.networking.gateway.uplinkGateway == "10.10.10.20"
  && relocatedSiteRoles.config.my.features.system.networking.tplink-ap.host == "10.10.10.1"
  && relocatedSiteRoles.config.my.features.system.networking.wireguard.primaryHub == "cld-ops-01"
  && cidrLib.prefixLength "fd10:1000:100::1/64" == 64
  && cidrLib.prefixLength "::ffff:192.0.2.1/128" == 128
  && cidrLib.prefixLength "0:0:0:0:0:ffff:192.0.2.1/128" == 128
  && cidrLib.prefixLength "2001:db8:0:0:0:0:0:1/128" == 128
  && cidrLib.prefixLength "::::/64" == null
  && cidrLib.prefixLength ":::/64" == null
  && cidrLib.prefixLength "2001:db8:::1/64" == null
  && cidrLib.prefixLength "2001::1:/64" == null
  && cidrLib.prefixLength "192.0.2.1::192.0.2.1/64" == null
  && cidrLib.prefixLength "2001:db8:gggg::1/64" == null
  && cidrLib.canonicalV6 "fd10:1000:100::20" == cidrLib.canonicalV6 "fd10:1000:100:0:0:0:0:20"
  && cidrLib.overlaps "10.10.20.0/24" "10.10.20.128/25"
  && cidrLib.overlaps "fd10:1000:100::/64" "fd10:1000:100::20/128"
  && cidrLib.containsV6 "fd10:1000:100::/64" "fd10:1000:100::20"
  && !cidrLib.containsV6 "fd10:1000:100::/64" "fd10:1000:101::20"
  && !cidrLib.containsV4 "fd10:1000:100::/64" "10.10.20.20"
then
  pkgs.runCommandLocal "topology-inventory-check" { } ''
    echo "second inventory, trust-level routing, address membership and independent negative controls passed" > "$out"
  ''
else
  throw "topology inventory fixture failed: expected trust-level routing and validated host/device address containment"
