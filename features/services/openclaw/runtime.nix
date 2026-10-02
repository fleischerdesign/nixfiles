{ lib, pkgs }:
{
  options = {
    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = "Native configuration for the pinned OpenClaw release; deeply merged by the JSON format type.";
    };
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Executables available to this runtime and its tools.";
    };
    enabledPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Identifiers from the repository plugin catalogue (features/services/openclaw/plugins.nix). The gateway closure carries them as bundled extensions; the consumer resolves the identifier to an allow/entry pair.";
    };
    skillDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Declarative skill roots added to native skill discovery.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret runtime environment.";
    };
    credentialFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variable to private runtime file; contents are read literally, never sourced as shell code.";
    };
    serviceConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional systemd service options, including resource limits.";
    };
  };

  build =
    {
      id,
      stateDir,
      package,
      runtime,
      settings,
    }:
    let
      configPath = "/etc/openclaw/${id}.json";
      resolved = lib.recursiveUpdate settings {
        update = {
          checkOnStart = false;
          auto.enabled = false;
        };
        skills.load.extraDirs =
          (settings.skills.load.extraDirs or [ ]) ++ map toString runtime.skillDirectories;
      };
      source = (pkgs.formats.json { }).generate "${id}.json" resolved;
      environment = runtime.environment // {
        OPENCLAW_STATE_DIR = stateDir;
        OPENCLAW_CONFIG_PATH = configPath;
        OPENCLAW_NIX_MODE = "1";
        OPENCLAW_NO_AUTO_UPDATE = "1";
        OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY = "1";
      };
      execute = pkgs.writeShellScriptBin "${id}-exec" ''
        set -euo pipefail
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (key: value: "export ${key}=${lib.escapeShellArg value}") environment
        )}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            key: path: ''export ${key}="$(< ${lib.escapeShellArg path})"''
          ) runtime.credentialFiles
        )}
        export PATH=${
          lib.escapeShellArg (
            lib.makeBinPath (
              [
                pkgs.bash
                pkgs.coreutils
              ]
              ++ runtime.packages
            )
          )
        }:"$PATH"
        cd ${lib.escapeShellArg stateDir}
        exec "$@"
      '';
      launcher = pkgs.writeShellScriptBin id ''
        exec ${execute}/bin/${id}-exec ${package}/bin/openclaw "$@"
      '';
    in
    {
      inherit
        configPath
        source
        environment
        execute
        launcher
        resolved
        ;
    };
}
