{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.opencode;
  upstream = pkgs.opencode-v2;
  credentialExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: path: ''
      ${name}="$(< ${lib.escapeShellArg path})"
      export ${name}
    '') cfg.credentialFiles
  );
  package = pkgs.writeShellScriptBin "opencode" ''
    set -euo pipefail
    ${credentialExports}
    exec ${upstream}/bin/opencode "$@"
  '';
in
{
  options.my.features.dev.opencode = {
    enable = lib.mkEnableOption "OpenCode v2 for Home Manager users";

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default provider/model identifier from the OpenCode v2 catalog.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional OpenCode v2 global configuration.";
    };

    credentialFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variable names mapped to runtime-readable secret files.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "OpenCode launcher with runtime credentials.";
    };
  };

  config = {
    my.features.dev.opencode.package = package;

    assertions = lib.optionals cfg.enable [
      {
        assertion = lib.all (name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null) (
          lib.attrNames cfg.credentialFiles
        );
        message = "OpenCode credentialFiles keys must be valid environment variable names.";
      }
    ];

    home-manager.sharedModules = [
      (
        { config, lib, ... }:
        let
          userCfg = config.my.features.dev.opencode;
          settings = lib.recursiveUpdate (
            {
              "$schema" = "https://opencode.ai/config.json";
              update = "disable";
            }
            // lib.optionalAttrs (cfg.model != null) { model = cfg.model; }
          ) cfg.settings;
        in
        {
          options.my.features.dev.opencode.enable = lib.mkEnableOption "OpenCode v2 for this user";

          config = lib.mkIf (cfg.enable && userCfg.enable) {
            home.packages = [ package ];
            xdg.configFile."opencode/opencode.json".text = builtins.toJSON settings;
          };
        }
      )
    ];
  };
}
