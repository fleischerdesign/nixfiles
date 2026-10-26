{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.dev.obsidian;
in
{
  options.my.features.dev.obsidian = {
    enable = lib.mkEnableOption "Obsidian Desktop with declarative configuration";

    vaultName = lib.mkOption {
      type = lib.types.str;
      default = "Main";
      description = "Default vault name for Obsidian.";
    };

    vaultTarget = lib.mkOption {
      type = lib.types.str;
      default = "Vaults/Main";
      description = "Relative path under home directory for the vault.";
    };

    livesync = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Declaratively configure Self-Hosted LiveSync plugin for Obsidian.";
      };

      couchdbUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://livesync.${config.my.topology.domain}";
        description = "CouchDB server URL for LiveSync.";
      };

      databaseName = lib.mkOption {
        type = lib.types.str;
        default = "obsidian-vault";
        description = "CouchDB database name for the vault.";
      };
    };

    plugins = {
      linter = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Linter community plugin.";
      };
      operon = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Operon plugin.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."services/storage/couchdb_obsidian_password" = { };
    sops.secrets."services/storage/couchdb_obsidian_passphrase" = { };

    # The plugin reads this file instead of its own settings UI, so every value the user might
    # change has to be declared here: anything missing returns to a plugin default at the next
    # activation. Three groups carry an invariant - the identity and chunk parameters must match
    # on every device (a mismatch re-chunks files and produces duplicate revisions), the plugin-sync
    # flags stay off because they write a second, competing settings file, and the plugin-managed
    # keys (settingVersion, doctorProcessedVersion) stay absent so the plugin migrates itself.
    sops.templates."obsidian_livesync_data.json" = {
      mode = "0444";
      content = builtins.toJSON {
        remoteType = "";
        couchDB_URI = cfg.livesync.couchdbUrl;
        couchDB_DBNAME = cfg.livesync.databaseName;
        couchDB_USER = "obsidian";
        couchDB_PASSWORD = config.sops.placeholder."services/storage/couchdb_obsidian_password";

        liveSync = true;
        syncOnStart = true;
        syncOnSave = true;
        syncOnFileOpen = true;
        periodicReplication = true;
        periodicReplicationInterval = 60;

        encrypt = true;
        E2EEAlgorithm = "v2";
        passphrase = config.sops.placeholder."services/storage/couchdb_obsidian_passphrase";

        enableChunkSplitterV2 = true;
        chunkSplitterVersion = "v3-rabin-karp";
        customChunkSize = 0;
        useDynamicIterationCount = true;
        idDerivationVersion = 0;
        pathNormalizationVersion = 0;

        usePluginSync = false;
        usePluginSyncV2 = false;

        writeDocumentsIfConflicted = false;
        trashInsteadDelete = true;
        checkIntegrityOnSave = true;
        syncMaxSizeInMB = 100;

        showStatusOnStatusbar = false;
        showStatusOnEditor = false;
        showOnlyIconsOnEditor = false;

        isConfigured = true;
      };
    };

    home-manager.sharedModules = [ ./home.nix ];
  };
}
