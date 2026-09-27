{ pkgs, ... }:
let
  fleetConfigs = import ../lib/fleet-configs.nix;

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
in
if
  # The fleet mapping passes through untouched, with every host's services visible.
  fleet == fleetFlake.nixosConfigurations
  && fleetConfigs.providesOf fleet.b == hostB.my.contracts.provides
  # Standalone evaluation and a flake without configurations fail loudly with a domain
  # message instead of projecting one host - or nothing - by accident.
  && !nullFlake.success
  && !emptyFlake.success
then
  pkgs.runCommandLocal "fleet-configs-check" { } ''
    echo "fleet pass-through, providesOf and loud rejection of null/empty flakes passed" > "$out"
  ''
else
  throw "fleet configs fixture failed: expected pass-through provides and loud null/empty rejection"
