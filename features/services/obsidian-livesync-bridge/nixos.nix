# features/services/obsidian-livesync-bridge/nixos.nix
# Multi-tenant Obsidian LiveSync Bridge service.
# Synchronizes CouchDB LiveSync remote vaults with local filesystem paths in real-time.
#
# Designed to be completely agnostic: supports arbitrary instances, customizable targets,
# and standalone vault setups.
{
  lib,
  pkgs,
  ...
}@topArgs:
let
  osConfig = topArgs.config;
  cfg = osConfig.my.features.services.obsidian-livesync-bridge;

  # The path an instance writes into, whether it named one or took the default. Defined once so the
  # bridge's target, the tmpfiles rule and the storage declaration cannot drift apart.
  effectiveVaultPath =
    name: inst:
    if inst.vaultPath != null then
      inst.vaultPath
    else
      "/var/lib/obsidian-livesync-bridge/vaults/${name}";

  instanceSubmodule =
    { name, config, ... }:
    let
      inst = config;

      targetVaultPath = effectiveVaultPath name inst;

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
            default = "https://livesync.${osConfig.my.topology.domain}";
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
            Defaults to /var/lib/obsidian-livesync-bridge/vaults/<name>.
          '';
        };

        replicaOnly = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Treat the vault as regenerable only when no local writer produces unreproduced changes.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "obsidian-bridge";
          description = "User account under which the bridge daemon runs.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "obsidian-bridge";
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
    # The vault is a replica: the bridge writes the notes *into* this directory from its CouchDB peer, so
    # the directory is regenerable and the origin - CouchDB on the edge - is the thing that is backed up.
    # Declared as regenerable rather than left for a host's broad backup path to sweep in.
    my.contracts.provides.obsidian-livesync-bridge = {
      storage.regenerableDirs = lib.mapAttrsToList effectiveVaultPath (
        lib.filterAttrs (_: inst: inst.replicaOnly) enabledInstances
      );
      storage.dataDirs = lib.mapAttrsToList effectiveVaultPath (
        lib.filterAttrs (_: inst: !inst.replicaOnly) enabledInstances
      );
    };

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

    users.users = lib.listToAttrs (
      lib.concatMap (
        inst:
        lib.optional (inst.user == "obsidian-bridge") {
          name = "obsidian-bridge";
          value = {
            isSystemUser = true;
            group = inst.group;
            description = "Obsidian LiveSync Bridge Daemon User";
          };
        }
      ) (lib.attrValues enabledInstances)
    );

    users.groups = lib.listToAttrs (
      lib.concatMap (
        inst:
        lib.optional (inst.group == "obsidian-bridge") {
          name = "obsidian-bridge";
          value = { };
        }
      ) (lib.attrValues enabledInstances)
    );

    # Ensure the vault directory exists with correct user ownership. The bridge's own state and cache
    # directories are created and owned by systemd (`StateDirectory=`, `CacheDirectory=`), which is
    # what keeps a stale owner from a removed account out of the Deno cache: a manual tmpfiles rule
    # sets the directory's owner once and leaves whatever is inside it untouched, and a UID that is
    # later reused by an unrelated account turns that into a silent read-only cache.
    systemd.tmpfiles.rules = lib.concatMap (
      name:
      let
        inst = enabledInstances.${name};
      in
      [
        "d ${inst._targetVaultPath} 0770 ${inst.user} ${inst.group} - -"
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
          cacheDir = "/var/cache/obsidian-livesync-bridge/${name}";
        in
        {
          name = "obsidian-livesync-bridge-${name}";
          value = {
            description = "Obsidian LiveSync Bridge (${name})";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            environment = {
              LSB_CONFIG = configFile;
              LSB_HEALTH_FILE = "${cacheDir}/health.json";
              # Deno's module cache and offline scan state both live here; `CacheDirectory` above
              # guarantees the running user owns it.
              DENO_DIR = cacheDir;
              HOME = stateDir;
            };

            serviceConfig = {
              User = inst.user;
              Group = inst.group;
              WorkingDirectory = stateDir;
              StateDirectory = "obsidian-livesync-bridge/${name}";
              StateDirectoryMode = "0750";
              CacheDirectory = "obsidian-livesync-bridge/${name}";
              CacheDirectoryMode = "0750";
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
