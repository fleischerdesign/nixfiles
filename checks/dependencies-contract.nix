{ pkgs, lib, ... }:
let
  fixture =
    {
      postgresqlEnabled ? true,
      database ? "fixture-db",
      user ? database,
      ensureDBOwnership ? true,
    }:
    (lib.evalModules {
      specialArgs = {
        inherit lib pkgs;
        fleetConfigs = {
          systems = _: { };
          providesOf = _: { };
        };
      };
      modules = [
        ../contracts/dependencies/nixos.nix
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
          options.networking.hostName = lib.mkOption {
            type = lib.types.str;
            default = "fixture";
          };
          options.services.postgresql.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          options.services.postgresql.ensureDatabases = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          options.services.postgresql.package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.postgresql;
          };
          options.services.postgresql.ensureUsers = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
          options.systemd.services = lib.mkOption {
            type = lib.types.attrsOf lib.types.attrs;
            default = { };
          };
          config.my.contracts.consumes.fixture.postgresql.main = {
            inherit database user ensureDBOwnership;
          };
          config.services.postgresql.enable = postgresqlEnabled;
        }
      ];
    }).config;

  valid = fixture { };
  missingProvider = fixture { postgresqlEnabled = false; };
  ownershipHandoff = fixture {
    database = "fixture-db";
    user = "fixture-role";
  };
  separateRoleWithoutOwnership = fixture {
    database = "fixture-db";
    user = "fixture-role";
    ensureDBOwnership = false;
  };
  failed = config: lib.filter (assertion: !assertion.assertion) config.assertions;
in
if
  failed valid == [ ]
  && valid.services.postgresql.ensureDatabases == [ "fixture-db" ]
  && failed missingProvider != [ ]
  && lib.any (assertion: lib.hasInfix "no local PostgreSQL provider" assertion.message) (
    failed missingProvider
  )
  && failed ownershipHandoff == [ ]
  && !(builtins.head ownershipHandoff.services.postgresql.ensureUsers).ensureDBOwnership
  && ownershipHandoff.systemd.services.postgresql-contract-ownership.before == [ "fixture.service" ]
  && !(separateRoleWithoutOwnership.systemd.services ? postgresql-contract-ownership)
  && failed separateRoleWithoutOwnership == [ ]
  &&
    (builtins.head separateRoleWithoutOwnership.services.postgresql.ensureUsers).name == "fixture-role"
  && !(builtins.head separateRoleWithoutOwnership.services.postgresql.ensureUsers).ensureDBOwnership
then
  pkgs.runCommandLocal "dependencies-contract-check" { } ''
    grep -F 'ALTER DATABASE "fixture-db" OWNER TO "fixture-role";' ${ownershipHandoff.systemd.services.postgresql-contract-ownership.serviceConfig.ExecStart} >/dev/null
    echo "provider presence and least-privilege PostgreSQL role/database ownership are validated" > "$out"
  ''
else
  throw "dependency contract fixture failed: expected missing-provider and incompatible-ownership rejection, while allowing an explicitly unowned separate role"
