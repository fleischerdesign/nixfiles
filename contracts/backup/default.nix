# contracts/backup/default.nix
# Declarative Backup Contract Specification (Clean Architecture & Reliability Engineering).
# Allows services to declare backup requirements, snapshot strategies, exclusions,
# and pre-dump hooks without coupling directly to restic, borg, or zfs implementations.
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

      preDumpHook = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Executable package/script to dump consistent state before transactional backup";
      };

      postDumpHook = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Executable package/script to clean up dump artifacts after transactional backup";
      };
    };
  };

  # Extract active backup contracts across all provided services on this host
  provides = config.my.contracts.provides or { };

  # Collect all backup paths across all services
  allBackupPaths = lib.concatLists (
    lib.mapAttrsToList (
      _svcName: svcContract:
      let
        bCfg = svcContract.backup or { };
        sCfg = svcContract.storage or { };
        customPaths = bCfg.paths or [ ];
        # Fallback to storage dataDirs + stateDirs if paths not explicitly specified
        storagePaths = (sCfg.dataDirs or [ ]) ++ (sCfg.stateDirs or [ ]);
      in
      if (bCfg.enable or false) then (if customPaths != [ ] then customPaths else storagePaths) else [ ]
    ) provides
  );

  allBackupExcludes = lib.concatLists (
    lib.mapAttrsToList (
      _svcName: svcContract:
      let
        bCfg = svcContract.backup or { };
        sCfg = svcContract.storage or { };
        customExcludes = bCfg.exclude or [ ];
        # Automatically exclude cacheDirs declared in storage contract
        cacheExcludes = sCfg.cacheDirs or [ ];
      in
      if (bCfg.enable or false) then (customExcludes ++ cacheExcludes) else [ ]
    ) provides
  );

  # Collect preDumpHooks into a composite pre-backup script if any exist
  preDumpHooks = lib.filter (hook: hook != null) (
    lib.mapAttrsToList (_svcName: svcContract: (svcContract.backup or { }).preDumpHook or null) provides
  );

  compositePreDump =
    if preDumpHooks != [ ] then
      pkgs.writeShellScript "restic-contract-pre-dump" (
        lib.concatStringsSep "\n" (map (hook: "${hook}") preDumpHooks)
      )
    else
      null;
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

  # Automatic projection into Restic backup feature if enabled on the host
  config = lib.mkIf (config.my.features.system.backups.restic.enable or false) {
    services.restic.backups.daily = {
      paths = allBackupPaths;
      exclude = allBackupExcludes;
    }
    // (lib.optionalAttrs (compositePreDump != null) {
      backupPreparePrune = "${compositePreDump}";
    });
  };
}
