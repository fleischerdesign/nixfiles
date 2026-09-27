# contracts/storage/nixos.nix
# Storage & Impermanence Contract Specification (Clean Architecture & docs/architecture.md 7.5).
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

      # Content that is regenerable - a media library, a download queue, a replica that can be pulled
      # again. It is declared because it exists, is not a cache, and must therefore not be mistaken for
      # either irreplaceable data or something nobody decided about. The backup contract reads it to
      # *exclude* it, which is what keeps a broad host path such as `/var/lib` from quietly pulling a
      # whole media library offsite.
      regenerableDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Regenerable content directories (media libraries, download queues, synced replicas) - declared, never backed up";
      };

      cacheDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Ephemeral cache directories (/var/cache) - safe to delete on reboot";
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
