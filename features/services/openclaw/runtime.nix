{
  lib,
  pkgs,
  inputs,
}:
let
  environment = import "${inputs.openclaw}/nix/modules/home-manager/openclaw/environment.nix" {
    inherit lib pkgs;
  };
in
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
    runtimePlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Official nix-openclaw runtime plugin identifiers; installed by its Home Manager module.";
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
      source ? null,
    }:
    let
      configPath = "/etc/openclaw/${id}.json";
      resolved = lib.recursiveUpdate settings {
        update = {
          checkOnStart = false;
          auto.enabled = false;
        };
      };
      configSource =
        if source != null then source else (pkgs.formats.json { }).generate "${id}.json" resolved;
      runtimeEnvironment =
        runtime.environment
        // runtime.credentialFiles
        // {
          OPENCLAW_STATE_DIR = stateDir;
          OPENCLAW_CONFIG_PATH = configPath;
          OPENCLAW_NIX_MODE = "1";
          OPENCLAW_NO_AUTO_UPDATE = "1";
          OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY = "1";
        };
      execute = pkgs.writeShellScriptBin "${id}-exec" ''
        set -euo pipefail
        ${environment.renderExports (
          lib.mapAttrsToList (key: value: { inherit key value; }) runtimeEnvironment
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
        execute
        launcher
        resolved
        ;
      source = configSource;
      environment = runtimeEnvironment;
    };
}
