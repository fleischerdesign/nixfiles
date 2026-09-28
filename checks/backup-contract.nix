{ pkgs, lib, ... }:
let
  fixture =
    {
      provider ? null,
      declined ? null,
    }:
    (lib.evalModules {
      specialArgs = { inherit lib; };
      modules = [
        ../contracts/projections/nixos.nix
        ../contracts/storage/nixos.nix
        ../contracts/backup/nixos.nix
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
          config.my.contracts.provides.example = {
            storage = {
              stateDirs = [ "/var/lib/example" ];
              dataDirs = [ "/data/example" ];
              cacheDirs = [ "/var/cache/example" ];
              regenerableDirs = [ "/data/regenerable" ];
            };
            backup = {
              exclude = [ "/tmp/example" ];
              preBackup = "prepare-example";
              postBackup = "cleanup-example";
            };
          };
          config.my.contracts.backupProviders = lib.optionalAttrs (provider != null) {
            ${provider} = {
              enable = provider != "declined";
              inherit declined;
            };
          };
        }
      ];
    }).config;
  active = fixture { provider = "arbitrary-backend"; };
  missing = fixture { };
  declined = fixture {
    provider = "declined";
    declined = "The target is intentionally ephemeral";
  };
  failures = config: lib.filter (assertion: !assertion.assertion) config.assertions;
  projection = active.my.contracts.projections.backup;
in
if
  failures active == [ ]
  && failures declined == [ ]
  && failures missing != [ ]
  &&
    projection.paths == [
      "/data/example"
      "/var/lib/example"
    ]
  &&
    projection.exclude == [
      "/tmp/example"
      "/var/cache/example"
      "/data/regenerable"
    ]
  && projection.preBackup == [ "prepare-example" ]
  && projection.postBackup == [ "cleanup-example" ]
then
  pkgs.runCommandLocal "backup-contract-check" { } ''
    echo "backend-neutral backup projection, lifecycle hooks and provider policy passed" > "$out"
  ''
else
  throw "backup contract fixture failed: expected neutral projections, provider recognition and explicit no-backup decisions"
