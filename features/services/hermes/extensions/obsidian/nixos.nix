# features/services/hermes/extensions/obsidian/nixos.nix — Obsidian LiveSync extension for Hermes
{
  config,
  lib,
  pkgs,
  ...
}:

let
  hcfg = config.my.features.services.hermes;
  ecfg = config.my.features.services.hermes.extensions.obsidian;
  livesyncCliPkg = pkgs.callPackage ./package.nix { };
in
{
  options.my.features.services.hermes.extensions.obsidian = {
    enable = lib.mkEnableOption "Obsidian LiveSync extension for Hermes agent";

    vaultPath = lib.mkOption {
      type = lib.types.str;
      default = "${hcfg.stateDir}/vault";
      description = "Path to synchronized vault directory on server.";
    };

    couchdbUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://livesync.mky.ancoris.ovh";
      description = "CouchDB URL for LiveSync.";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "obsidian-vault";
      description = "CouchDB database name.";
    };
  };

  config = lib.mkIf (hcfg.enable && ecfg.enable) {
    sops.secrets.couchdb_obsidian_password = {
      sopsFile = ../../../../../secrets/secrets.yaml;
    };

    sops.templates."hermes_obsidian_livesync_data.json" = {
      mode = "0444";
      content = builtins.toJSON {
        remoteType = 0;
        couchDB_URI = ecfg.couchdbUrl;
        couchDB_DBNAME = ecfg.databaseName;
        couchDB_USER = "obsidian";
        couchDB_PASSWORD = config.sops.placeholder.couchdb_obsidian_password;
        couchdb_url = ecfg.couchdbUrl;
        couchdb_dbname = ecfg.databaseName;
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

    systemd.services.obsidian-livesync-hermes = {
      description = "Obsidian LiveSync Daemon for Hermes Agent";
      wantedBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent.service" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.nodejs ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        Group = "hermes";
        Restart = "always";
        RestartSec = "10s";
        ExecStartPre = pkgs.writeShellScript "obsidian-livesync-hermes-pre" ''
          mkdir -p "${ecfg.vaultPath}/.livesync"
          mkdir -p "${ecfg.vaultPath}/Wiki"
          cp -f "/run/secrets/rendered/hermes_obsidian_livesync_data.json" "${ecfg.vaultPath}/.livesync/settings.json"
        '';
        ExecStart = "${livesyncCliPkg}/bin/livesync-cli ${ecfg.vaultPath} --vault ${ecfg.vaultPath} daemon";
      };
    };

    services.hermes-agent.settings = {
      skills = {
        research-llm-wiki = {
          enabled = true;
          wiki_path = "${ecfg.vaultPath}/Wiki";
        };
      };
    };
  };
}
