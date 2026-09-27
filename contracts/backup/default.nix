# contracts/backup/default.nix
# Declarative Backup Contract Specification (Clean Architecture & Reliability Engineering).
# Allows services to declare backup requirements, snapshot strategies, exclusions,
# and consistency hooks without coupling directly to restic, borg, or zfs implementations.
{
  config,
  lib,
  pkgs,
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

  # One script per phase, run by the backup job itself. `set -euo pipefail` makes the composite stop at
  # the first hook that fails, instead of carrying on to back up half-written state and reporting success.
  compositeHook =
    field:
    let
      hooks = hooksOf field;
    in
    if hooks == [ ] then
      null
    else
      pkgs.writeShellScript "restic-contract-${field}" ''
        set -euo pipefail
        ${lib.concatStringsSep "\n" hooks}
      '';

  preBackup = compositeHook "preBackup";
  postBackup = compositeHook "postBackup";

  restic = config.my.features.system.backups.restic;
in
{
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

  config = lib.mkMerge [
    {
      # A host that declares state worth restoring and then runs no backup is a decision only if it is
      # written down. This refuses the alternative - an omission that looks exactly like a policy.
      assertions = [
        {
          assertion = (restic.enable or false) || allBackupPaths == [ ] || (restic.declined or null) != null;
          message = ''
            this host declares state that must be restorable (${lib.concatStringsSep ", " allBackupPaths})
            but runs no restic backup. Either enable my.features.system.backups.restic, or state why this
            host is deliberately without one (my.features.system.backups.restic.declined).
          '';
        }
      ];
    }
    # `lib.mkIf` and not `lib.optionalAttrs`: the condition reads the restic feature through `config`, and
    # `optionalAttrs` forces it while this module's config is being built - a fixpoint reached too early,
    # which is an infinite recursion. `mkIf` keeps the condition lazy, the way the previous shape did.
    (lib.mkIf (restic.enable or false) {
      # Projection into the Restic feature when the host runs it. The hooks run inside the job, so a
      # failed dump fails the backup rather than leaving a stale dump that looks fresh.
      services.restic.backups.daily = {
        paths = allBackupPaths;
        exclude = allBackupExcludes;
      }
      // lib.optionalAttrs (preBackup != null) { backupPrepareCommand = "${preBackup}"; }
      // lib.optionalAttrs (postBackup != null) { backupCleanupCommand = "${postBackup}"; };
    })
  ];
}
