{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.opencodex;
in
{
  options.my.features.dev.opencodex = {
    enable = lib.mkEnableOption "Local OpenCodex provider proxy for Home Manager users";
    port = lib.mkOption {
      type = lib.types.port;
      default = 10100;
      description = "Loopback port for the proxy and dashboard.";
    };
    credentialFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables read from runtime secret files by the proxy.";
    };
  };
  config = {
    assertions = lib.optionals cfg.enable [
      {
        assertion = config.my.features.dev.codex.enable;
        message = "OpenCodex requires the Codex feature.";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "OpenCodex is packaged for x86_64-linux.";
      }
      {
        assertion = lib.all (name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null) (
          lib.attrNames cfg.credentialFiles
        );
        message = "OpenCodex credentialFiles keys must be environment variable names.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
