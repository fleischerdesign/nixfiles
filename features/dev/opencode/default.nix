# features/dev/opencode/default.nix — Generic OpenCode Home-Manager & System Feature Module
#
# Architecture & Guidelines:
# - System Level: Defines host-level `providers` (SOPS auth.json template) and `settings`.
# - User-Scoped Level (`home-manager.sharedModules`): Exposes `my.features.dev.opencode.enable` for HM users.
# - Agnostic & Generic: Zero hardcoded usernames, hostnames, or paths. Reusable across NixOS & Home Manager.
# - Single Source of Truth: Base skills, agents, instructions defined once under `features/dev/opencode/`.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.opencode;
  opencodeDir = ./.;
in
{
  options.my.features.dev.opencode = {
    enable = lib.mkEnableOption "system-wide OpenCode API secrets template";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Host-wide default OpenCode settings (model, mcp, plugins, etc.).";
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
      description = "Provider API keys for system-wide auth.json template generation.";
    };
  };

  config = lib.mkMerge [
    # System-level SOPS secrets template if providers are defined
    (lib.mkIf (cfg.enable || cfg.providers != { }) {
      sops.templates."opencode-auth.json" = lib.mkIf (cfg.providers != { }) {
        owner = config.my.user.primary or "root";
        group = "users";
        mode = "0440";
        content = builtins.toJSON (
          lib.mapAttrs (_: p: {
            type = "api";
            key = p.apiKey;
          }) cfg.providers
        );
      };
    })

    # Home-Manager module registered for all users on the host
    {
      home-manager.sharedModules = [
        (
          {
            config,
            lib,
            pkgs,
            osConfig ? { },
            ...
          }:
          let
            userCfg = config.my.features.dev.opencode;
          in
          {
            options.my.features.dev.opencode = {
              enable = lib.mkEnableOption "OpenCode AI assistant for this Home Manager user";

              settings = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = "User-specific OpenCode settings (model, plugins, mcp, etc.).";
              };

              skills = lib.mkOption {
                type = lib.types.path;
                default = opencodeDir + "/skills";
                description = "Path to skills directory.";
              };

              agents = lib.mkOption {
                type = lib.types.path;
                default = opencodeDir + "/agents";
                description = "Path to agents directory.";
              };
            };

            config = lib.mkIf userCfg.enable {
              programs.opencode = {
                enable = true;
                extraPackages = [ pkgs.nodejs ];
                skills = userCfg.skills;
                agents = userCfg.agents;
                settings = lib.mkMerge [
                  {
                    model = lib.mkDefault "deepseek/deepseek-v4-pro";
                    small_model = lib.mkDefault "deepseek/deepseek-v4-flash";
                    autoupdate = lib.mkDefault false;
                    instructions = lib.mkDefault [
                      "~/.config/opencode/instructions/engineering-constitution.md"
                    ];
                    mcp = {
                      nixos = {
                        type = "local";
                        command = [ "${pkgs.mcp-nixos}/bin/mcp-nixos" ];
                        enabled = true;
                      };
                      chrome-devtools = {
                        type = "local";
                        command = [
                          "npx"
                          "-y"
                          "chrome-devtools-mcp@latest"
                          "--executablePath"
                          "${pkgs.google-chrome}/bin/google-chrome-stable"
                        ];
                        enabled = true;
                      };
                    };
                    plugin = [
                      "context-mode"
                      "opencode-pty"
                      "opencode-direnv"
                    ];
                  }
                  (osConfig.my.features.dev.opencode.settings or { })
                  userCfg.settings
                ];
              };

              home.file = {
                ".config/opencode/instructions/engineering-constitution.md".source =
                  opencodeDir + "/instructions/engineering-constitution.md";

                ".local/share/opencode/auth.json" =
                  lib.mkIf (osConfig ? sops && osConfig.sops.templates ? "opencode-auth.json")
                    {
                      source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates."opencode-auth.json".path;
                    };
              };
            };
          }
        )
      ];
    }
  ];
}
