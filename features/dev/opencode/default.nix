# features/dev/opencode/default.nix — Shared OpenCode configuration module
#
# Single Source of Truth for OpenCode settings consumed by multiple
# users (philipp via Home-Manager, hermes via NixOS tmpfiles).
#
# Design:
#   settings   → pkgs.writeText → plain store path (no secrets)
#   providers  → sops.templates → encrypted auth.json (API keys via SOPS)
#
# Every consumer reads my.features.dev.opencode.* options and applies
# them in its own context — no implicit user lists, no hardcodes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.opencode;
in
{
  options.my.features.dev.opencode = {
    enable = lib.mkEnableOption "shared OpenCode configuration";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "OpenCode settings (model, mcp, plugin, provider.*, instructions, etc.).";
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            apiKey = lib.mkOption {
              type = lib.types.str;
              description = "API key, typically from config.sops.placeholder.";
            };
          };
        }
      );
      default = { };
      description = "Provider API keys for auth.json generation.";
    };

    configJsonPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      internal = true;
      description = "Nix store path to generated opencode.json (plain, no secrets).";
    };

    authJsonPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Decrypted opencode auth.json path. Prefer referencing config.sops.templates.\"opencode-auth.json\".path directly.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.dev.opencode.configJsonPath = pkgs.writeText "opencode-config.json" (
      builtins.toJSON cfg.settings
    );

    sops.templates."opencode-auth.json" = lib.mkIf (cfg.providers != { }) {
      owner = config.my.user.primary;
      group = "users";
      mode = "0440";
      content = builtins.toJSON (
        lib.mapAttrs (_: p: {
          type = "api";
          key = p.apiKey;
        }) cfg.providers
      );
    };

    systemd.tmpfiles.rules =
      let
        primaryUser = config.my.user.primary or null;
        primaryHome =
          if primaryUser != null && config.users.users ? ${primaryUser} then
            config.users.users.${primaryUser}.home
          else
            null;
        hermesHome = if config.users.users ? hermes then config.users.users.hermes.home else null;
        authPath = config.sops.templates."opencode-auth.json".path;
      in
      lib.mkIf (cfg.providers != { }) (
        (lib.optionals (primaryUser != null && primaryHome != null) [
          "d ${primaryHome}/.local/share/opencode 0700 ${primaryUser} users - -"
          "L+ ${primaryHome}/.local/share/opencode/auth.json 0600 ${primaryUser} users - ${authPath}"
        ])
        ++ (lib.optionals (hermesHome != null) [
          "d ${hermesHome}/.local/share/opencode 0700 hermes users - -"
          "L+ ${hermesHome}/.local/share/opencode/auth.json 0600 hermes users - ${authPath}"
        ])
      );
  };
}
