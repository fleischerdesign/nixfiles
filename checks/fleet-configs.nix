{ pkgs, lib, ... }:
let
  fleetConfigs = import ../lib/fleet-configs.nix { inherit lib; };

  hostA = {
    networking.hostName = "a";
    _module.specialArgs.flake = null;
    my.contracts.provides.svc-a.endpoints.web.port = 1;
  };
  hostB = {
    networking.hostName = "b";
    _module.specialArgs.flake = null;
    my.contracts.provides.svc-b.endpoints.web.port = 2;
  };
  fleetFlake = {
    nixosConfigurations = {
      a = {
        config = hostA;
      };
      b = {
        config = hostB;
      };
    };
  };
  fleetReader = hostA // {
    _module.specialArgs.flake = fleetFlake;
  };

  fleet = fleetConfigs.systems fleetReader;
  nullFlake = builtins.tryEval (fleetConfigs.systems hostA);
  emptyFlake = builtins.tryEval (
    fleetConfigs.systems (hostA // { _module.specialArgs.flake = { }; })
  );

  roleSystems = {
    a = {
      config = {
        role = "hub";
      };
    };
    b = {
      config = {
        role = "spoke";
      };
    };
  };
  pickHub =
    systems:
    fleetConfigs.uniqueHost {
      inherit systems;
      matches = hostCfg: hostCfg.role or null == "hub";
      role = "hub";
    };
  oneHub = pickHub roleSystems;
  noHub = builtins.tryEval (pickHub { });
  twoHubs = builtins.tryEval (pickHub {
    a = {
      config = {
        role = "hub";
      };
    };
    b = {
      config = {
        role = "hub";
      };
    };
  });
in
if
  # The fleet mapping passes through untouched, with every host's services visible.
  fleet == fleetFlake.nixosConfigurations
  && fleetConfigs.providesOf fleet.b == hostB.my.contracts.provides
  # Standalone evaluation and a flake without configurations fail loudly with a domain
  # message instead of projecting one host - or nothing - by accident.
  && !nullFlake.success
  && !emptyFlake.success
  # Provider selection is exact: one candidate wins, zero or several fail loudly.
  && oneHub == "a"
  && !noHub.success
  && !twoHubs.success
then
  pkgs.runCommandLocal "fleet-configs-check" { } ''
    echo "fleet pass-through, providesOf, unique provider and loud rejections passed" > "$out"
  ''
else
  throw "fleet configs fixture failed: expected pass-through provides, exact provider selection and loud rejections"
