{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.dev.obsidian;

  # The plugin stores connections as sls+ URIs: the original scheme becomes the sub-scheme and
  # the database name moves into a query parameter.
  livesyncUrl = cfg.livesync.couchdbUrl;
  scheme = lib.head (builtins.match "([a-z]+)://.*" livesyncUrl);
  hostPath = lib.removePrefix "${scheme}://" livesyncUrl;
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

        # Without an entry here the plugin re-migrates the legacy fields on every start and
        # announces it; the URI is the plugin's own sls+ form with the database as `db`.
        remoteConfigurations = {
          legacy-couchdb = {
            id = "legacy-couchdb";
            name = "CouchDB Remote";
            uri = "sls+${scheme}://obsidian:${
              config.sops.placeholder."services/storage/couchdb_obsidian_password"
            }@${hostPath}?db=${cfg.livesync.databaseName}";
            isEncrypted = false;
          };
        };
        activeConfigurationId = "legacy-couchdb";

        # The plugin refuses customisation sync without a device name; the host name makes it
        # unique per device, and the phone sets its own.
        deviceAndVaultName = config.networking.hostName;

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

        # Customisation scan: without this flag the plugin never scans plugin settings on its
        # own - the `ix:` documents only appear when the command runs manually.
        autoSweepPlugins = true;

        # Customisation sync is the only channel by which plugin settings reach unmanaged
        # devices (phone, tablet). V2 stores them per file; the older flag is its master
        # switch, so both are on. What Nix still owns - the plugin list and the template
        # folder - is rewritten at each activation and the sync follows it.
        usePluginSync = true;
        usePluginSyncV2 = true;

        writeDocumentsIfConflicted = false;
        trashInsteadDelete = true;
        checkIntegrityOnSave = true;
        syncMaxSizeInMB = 100;

        showStatusOnStatusbar = false;
        showStatusOnEditor = false;
        showOnlyIconsOnEditor = false;

        # Both toasts below are prompts for unset values: the plugin asks for a remote storage
        # threshold while the setting is negative, and it announces translation packs it found.
        # The interface stays English: `def` is the plugin's own value for the default language.
        displayLanguage = "def";
        notifyThresholdOfRemoteStorageSize = 0;

        isConfigured = true;
      };
    };

    home-manager.sharedModules = [ ./home.nix ];
  };
}
