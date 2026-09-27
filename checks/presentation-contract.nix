{ pkgs, lib }:
let
  fixture =
    tiles:
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
                  type = lib.types.attrsOf lib.types.attrs;
                  default = { };
                };
              }
            );
          };
        }
        ../contracts/portal/nixos.nix
        {
          my.contracts.provides.example = {
            endpoints.web = { };
            presentation.tiles = tiles;
          };
        }
      ];
    }).config;
  failures = tiles: lib.filter (check: !check.assertion) (fixture tiles).assertions;
in
if
  failures { main.endpoint = "web"; } == [ ]
  && lib.any (entry: lib.hasInfix "unknown endpoint 'missing'" entry.message) (failures {
    main.endpoint = "missing";
  })
  &&
    lib.any (entry: lib.hasInfix "description must name every portal locale" entry.message)
      (failures {
        main = {
          endpoint = "web";
          description.de = "Nur Deutsch";
        };
      })
then
  pkgs.runCommandLocal "presentation-contract-check" { } ''
    echo "named tile reference and localized copy negative controls passed" > "$out"
  ''
else
  throw "presentation contract fixture failed: invalid endpoint or missing locale accepted"
