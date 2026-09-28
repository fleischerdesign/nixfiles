# contracts/backup/nixos.nix
# Declarative Backup Contract Specification (Clean Architecture & Reliability Engineering).
# Allows services to declare backup requirements, snapshot strategies, exclusions,
# and consistency hooks without coupling directly to restic, borg, or zfs implementations.
{
  config,
  lib,
  ...
}:
let
  backupContractSubmodule = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this service's persistent storage should be included in backup snapshots";
      };

      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Explicit filesystem paths to back up (if empty, automatically populated from storage contract)";
      };

      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "File patterns or directories to exclude from backup snapshots (e.g. cache, temp dirs)";
      };

      # The consistency hooks are shell code that runs inside the backup job, so their failure fails the
      # backup - the property that makes a dump trustworthy. They map to the NixOS options of the same
      # purpose (`backupPrepareCommand` / `backupCleanupCommand`); the previous shape wrote a
      # `backupPreparePrune` option the module does not have, so no hook could be declared at all.
      preBackup = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "Shell code run before the backup starts, to produce a consistent dump (e.g. pg_dumpall)";
      };

      postBackup = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "Shell code run after the backup finishes, to clean up the dump artifacts";
      };
    };
  };

  # Every service contract declared on this host, and the two sub-contracts the backup reads.
  contracts = lib.attrValues (config.my.contracts.provides or { });

  backupOf = contract: contract.backup or { };
  storageOf = contract: contract.storage or { };
  enabled = contract: (backupOf contract).enable or false;

  pathsOf =
    contract:
    let
      explicit = (backupOf contract).paths or [ ];
      storage = storageOf contract;
    in
    if explicit != [ ] then explicit else (storage.dataDirs or [ ]) ++ (storage.stateDirs or [ ]);

  allBackupPaths = lib.unique (lib.concatMap pathsOf (lib.filter enabled contracts));

  allBackupExcludes = lib.unique (
    lib.concatMap (
      contract:
      if enabled contract then
        ((backupOf contract).exclude or [ ]) ++ ((storageOf contract).cacheDirs or [ ])
      else
        [ ]
    ) contracts
    # Content is excluded whether or not its service is backed up: the declaration says this is
    # regenerable, and regenerable content is not what the backup is for - not even when a host declares
    # a broad path that would otherwise sweep it in.
    ++ lib.concatMap (contract: (storageOf contract).regenerableDirs or [ ]) contracts
  );

  hooksOf =
    field:
    map (contract: (backupOf contract).${field}) (
      lib.filter (contract: enabled contract && (backupOf contract).${field} != null) contracts
    );

  backupProviders = config.my.contracts.backupProviders;
  activeProvider = lib.any (provider: provider.enable) (lib.attrValues backupProviders);
  declaredDecline = lib.any (provider: provider.declined != null) (lib.attrValues backupProviders);
in
{
  options.my.contracts.backupProviders = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this backup provider";
          declined = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Explicit reason this host has no backup provider.";
          };
        };
      }
    );
    default = { };
    description = "Backup backends installed on this host and explicit no-backup decisions.";
  };

  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.backup = lib.mkOption {
          type = backupContractSubmodule;
          default = { };
          description = "Backup lifecycle and consistency declarations";
        };
      }
    );
  };

  config = {
    my.contracts.projections.backup = {
      paths = allBackupPaths;
      exclude = allBackupExcludes;
      preBackup = hooksOf "preBackup";
      postBackup = hooksOf "postBackup";
    };
    # A host that declares state worth restoring and then runs no backup is a decision only if it is
    # written down. This refuses the alternative - an omission that looks exactly like a policy.
    assertions = [
      {
        assertion = activeProvider || allBackupPaths == [ ] || declaredDecline;
        message = ''
          this host declares state that must be restorable (${lib.concatStringsSep ", " allBackupPaths})
          but has no enabled backup provider. Enable an appropriate backend or record an explicit
          no-backup decision in my.contracts.backupProviders.<backend>.declined.
        '';
      }
    ];
  };
}
