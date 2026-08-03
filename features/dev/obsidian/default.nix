{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.dev.obsidian;

  mkPluginFromManifest =
    manifestPath:
    let
      m = builtins.fromJSON (builtins.readFile manifestPath);
      tag = "${m.upstream.tagPrefix or ""}${m.version}";
    in
    pkgs.stdenv.mkDerivation {
      pname = m.pname;
      version = m.version;
      srcs = [
        (pkgs.fetchurl {
          url = "https://github.com/${m.upstream.owner}/${m.upstream.repo}/releases/download/${tag}/main.js";
          sha256 = m.mainHash;
        })
        (pkgs.fetchurl {
          url = "https://github.com/${m.upstream.owner}/${m.upstream.repo}/releases/download/${tag}/manifest.json";
          sha256 = m.manifestHash;
        })
      ]
      ++ lib.optionals (m.stylesHash or "" != "") [
        (pkgs.fetchurl {
          url = "https://github.com/${m.upstream.owner}/${m.upstream.repo}/releases/download/${tag}/styles.css";
          sha256 = m.stylesHash;
        })
      ];
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out
        for src in $srcs; do
          cp $src $out/$(stripHash $src)
        done
      '';
    };

  obsidianLiveSyncPkg = mkPluginFromManifest ./plugins/livesync/manifest.json;
  obsidianTemplaterPkg = mkPluginFromManifest ./plugins/templater/manifest.json;
  obsidianDataviewPkg = mkPluginFromManifest ./plugins/dataview/manifest.json;
  obsidianLinterPkg = mkPluginFromManifest ./plugins/linter/manifest.json;
  obsidianMetaBindPkg = mkPluginFromManifest ./plugins/meta-bind/manifest.json;
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
        default = "https://livesync.mky.ancoris.ovh";
        description = "CouchDB server URL for LiveSync.";
      };

      databaseName = lib.mkOption {
        type = lib.types.str;
        default = "obsidian-vault";
        description = "CouchDB database name for the vault.";
      };
    };

    plugins = {
      templater = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Templater community plugin.";
      };
      dataview = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Dataview community plugin.";
      };
      linter = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Linter community plugin.";
      };
      metaBind = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install Meta Bind community plugin.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.couchdb_obsidian_password = {
      sopsFile = ../../../secrets/secrets.yaml;
    };

    sops.templates."obsidian_livesync_data.json" = {
      mode = "0444";
      content = builtins.toJSON {
        remoteType = 0;
        couchDB_URI = cfg.livesync.couchdbUrl;
        couchDB_DBNAME = cfg.livesync.databaseName;
        couchDB_USER = "obsidian";
        couchDB_PASSWORD = config.sops.placeholder.couchdb_obsidian_password;
        couchdb_url = cfg.livesync.couchdbUrl;
        couchdb_dbname = cfg.livesync.databaseName;
        couchdb_user = "obsidian";
        couchdb_password = config.sops.placeholder.couchdb_obsidian_password;
        liveSync = true;
        syncOnSave = true;
        syncOnStart = true;
        syncOnFileOpen = true;
        periodicReplication = true;
        periodicReplicationInterval = 60;
        isConfigured = true;
        preset = "livesync";
        isCustomizationOpen = false;
        isManualSettingsOpen = false;
        autoApplyCustomization = true;
        useDynamicIterationCount = true;
        usePluginSyncV2 = true;
        customChunkSize = 60;
        enableChunkSplitterV2 = true;
        E2EEAlgorithm = 2;
        doctorProcessedVersion = "1.0.0";
        setupFinish = true;
        settingVersion = 2;
      };
    };

    home-manager.sharedModules = [
      (
        { config, ... }:
        {
          programs.obsidian = {
            enable = true;
            cli.enable = true;

            vaults.${cfg.vaultName} = {
              target = cfg.vaultTarget;
              settings = {
                communityPlugins =
                  lib.optionals cfg.livesync.enable [
                    {
                      pkg = obsidianLiveSyncPkg;
                    }
                  ]
                  ++ lib.optionals cfg.plugins.templater [ obsidianTemplaterPkg ]
                  ++ lib.optionals cfg.plugins.dataview [ obsidianDataviewPkg ]
                  ++ lib.optionals cfg.plugins.linter [ obsidianLinterPkg ]
                  ++ lib.optionals cfg.plugins.metaBind [ obsidianMetaBindPkg ];
              };
            };
          };

          home.file."${cfg.vaultTarget}/.obsidian/plugins/obsidian-livesync/data.json" =
            lib.mkIf cfg.livesync.enable
              {
                source = config.lib.file.mkOutOfStoreSymlink "/run/secrets/rendered/obsidian_livesync_data.json";
              };
        }
      )
    ];
  };
}
