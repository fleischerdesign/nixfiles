# contracts/storage/default.nix
# Storage & Impermanence Contract Specification (Clean Architecture & docs/architecture.md 8.5).
# Declares persistence boundaries (state, data, cache) and backup hooks for services.
{
  lib,
  ...
}:

let
  # Submodule for Storage & Impermanence Contract
  storageContractSubmodule = lib.types.submodule {
    options = {
      stateDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Machine-generated state directories to persist across ephemeral reboots (/persist/state)";
      };

      dataDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Irreplaceable user data directories (/persist/data) - mandatory Tier-3 backup";
      };

      cacheDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Ephemeral cache directories (/var/cache) - safe to delete on reboot";
      };

      preBackupHook = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Idempotent script to dump consistent state before transactional backup";
      };
    };
  };
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.storage = lib.mkOption {
          type = storageContractSubmodule;
          default = { };
          description = "Storage persistence and state lifecycle declaration";
        };
      }
    );
  };
}
