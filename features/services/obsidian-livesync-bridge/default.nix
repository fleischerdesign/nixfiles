# features/services/obsidian-livesync-bridge/default.nix
# Multi-tenant Obsidian LiveSync Bridge service.
# Synchronizes CouchDB LiveSync remote vaults with local filesystem paths in real-time.
#
# Designed to be completely agnostic: supports arbitrary instances, customizable targets,
# and integrates cleanly with OpenClaw or standalone vault setups.
{
  lib,
  pkgs,
  ...
}@topArgs:
let
  osConfig = topArgs.config;
  cfg = osConfig.my.features.services.obsidian-livesync-bridge;

  instanceSubmodule =
    { name, config, ... }:
    let
      inst = config;

      targetVaultPath =
        if inst.vaultPath != null then inst.vaultPath else "/var/lib/openclaw/instances/${name}/obsidian";

      rawConfig = {
        peers = [
          (
            {
              type = "couchdb";
              name = "remote-${name}";
              url = inst.couchdb.url;
              database = inst.couchdb.database;
              username = inst.couchdb.username;
              password = osConfig.sops.placeholder.${inst.couchdb.passwordSecret};
              baseDir = "";
            }
            // lib.optionalAttrs (inst.couchdb.passphraseSecret != null) {
              passphrase = osConfig.sops.placeholder.${inst.couchdb.passphraseSecret};
            }
          )
          {
            type = "storage";
            name = "local-${name}";
            baseDir = targetVaultPath;
            useChokidar = true;
          }
        ];
      };

      secretNames = lib.filter (s: s != null && s != "") [
        inst.couchdb.passwordSecret
        inst.couchdb.passphraseSecret
      ];
    in
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable this LiveSync bridge instance.";
        };

        couchdb = {
          url = lib.mkOption {
            type = lib.types.str;
            default = "https://livesync.edge.${config.my.topology.domain}";
            description = "CouchDB server URL.";
          };

          database = lib.mkOption {
            type = lib.types.str;
            default = "obsidian-vault";
            description = "CouchDB database name.";
          };

          username = lib.mkOption {
            type = lib.types.str;
            default = "obsidian";
            description = "CouchDB username.";
          };

          passwordSecret = lib.mkOption {
            type = lib.types.str;
            default = "services/storage/couchdb_obsidian_password";
            description = "SOPS secret key holding the CouchDB user password.";
          };

          passphraseSecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional SOPS secret key holding the E2EE passphrase.";
          };
        };

        vaultPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Filesystem path to synchronize notes into.
            Defaults to /var/lib/openclaw/instances/<name>/obsidian.
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "openclaw";
          description = "User account under which the bridge daemon runs.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "openclaw";
          description = "Group under which the bridge daemon runs.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.custom.livesync-bridge;
          description = "livesync-bridge package to run.";
        };

        # Computed internal attributes
        _targetVaultPath = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = targetVaultPath;
        };

        _rawConfig = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          default = rawConfig;
        };

        _secretNames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          default = secretNames;
        };
      };
    };

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) cfg.instances;
in
{
  options.my.features.services.obsidian-livesync-bridge = {
    enable = lib.mkEnableOption "Obsidian LiveSync Bridge service";

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceSubmodule);
      default = { };
      description = "Declared Obsidian LiveSync bridge instances.";
    };
  };

  config = lib.mkIf (cfg.enable && enabledInstances != { }) {
    # Ensure SOPS secrets used by any instance are registered
    sops.secrets = lib.genAttrs (lib.unique (
      lib.concatMap (inst: inst._secretNames) (lib.attrValues enabledInstances)
    )) (_: { });

    # Generate isolated config files via sops.templates (keeps passwords out of Nix store)
    sops.templates = lib.listToAttrs (
      map (
        name:
        let
          inst = enabledInstances.${name};
        in
        {
          name = "obsidian_livesync_bridge_${name}_config";
          value = {
            owner = inst.user;
            group = inst.group;
            mode = "0600";
            restartUnits = [ "obsidian-livesync-bridge-${name}.service" ];
            content = builtins.toJSON inst._rawConfig;
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    # Ensure vault and state directories exist with correct user ownership
    systemd.tmpfiles.rules = lib.concatMap (
      name:
      let
        inst = enabledInstances.${name};
      in
      [
        "d ${inst._targetVaultPath} 0770 ${inst.user} ${inst.group} - -"
        "d /var/lib/obsidian-livesync-bridge/${name} 0750 ${inst.user} ${inst.group} - -"
      ]
    ) (lib.attrNames enabledInstances);

    # Systemd services for each enabled bridge instance
    systemd.services = lib.listToAttrs (
      map (
        name:
        let
          inst = enabledInstances.${name};
          configFile = osConfig.sops.templates."obsidian_livesync_bridge_${name}_config".path;
          stateDir = "/var/lib/obsidian-livesync-bridge/${name}";
        in
        {
          name = "obsidian-livesync-bridge-${name}";
          value = {
            description = "Obsidian LiveSync Bridge (${name})";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "tailscaled.service"
            ];
            wants = [ "network-online.target" ];

            environment = {
              LSB_CONFIG = configFile;
              LSB_HEALTH_FILE = "${stateDir}/health.json";
              DENO_DIR = "${stateDir}/.deno";
              HOME = stateDir;
            };

            serviceConfig = {
              User = inst.user;
              Group = inst.group;
              WorkingDirectory = stateDir;
              ExecStart = "${inst.package}/bin/livesync-bridge";
              Restart = "always";
              RestartSec = 5;
            };

            path = [
              pkgs.deno
              pkgs.coreutils
            ];
          };
        }
      ) (lib.attrNames enabledInstances)
    );
  };
}
