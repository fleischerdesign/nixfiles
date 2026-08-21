# features/dev/pi/default.nix — Generic Pi coding-agent Home-Manager & System Feature Module
#
# Architecture & Guidelines:
# - System Level: Defines models (tiered), providers (SOPS auth.json template), settings, and MCP servers.
# - User-Scoped Level (home-manager.sharedModules): Exposes my.features.dev.pi.enable for HM users.
# - Agnostic & Generic: Zero hardcoded usernames, hostnames, or paths. Reusable across NixOS & Home Manager.
# - Single Source of Truth: Skills, agents, instructions, and plugins defined once under features/dev/pi/.
# - Model Indirection: Agents reference tiers (primary/secondary); actual model strings live in `models.*`
#   and surface via `subagents.agentOverrides` in the generated settings.json.
# - Plugins: Auto-discovered + built via lib/plugins.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.pi;
  piDir = ./.;
  pluginsLib = import ./lib/plugins.nix { inherit lib pkgs; };
  # Fine-grained agent configuration: Tier & Reasoning Effort per agent role.
  # - Reviewers / Auditors (primary): high capability + high reasoning (quality gate must never compromise).
  # - Implementer (secondary): cost-efficient + low reasoning (executes spec & TDD, saves ~80% output tokens).
  # - Explorer (tertiary): ultra-cheap + low reasoning (fast file gathering & repo searches).
  agentConfigs = {
    implement = {
      tier = "secondary";
      thinkingLevel = "low";
    };
    review = {
      tier = "primary";
      thinkingLevel = "high";
    };
    security-reviewer = {
      tier = "primary";
      thinkingLevel = "high";
    };
    explore = {
      tier = "tertiary";
      thinkingLevel = "low";
    };
  };
in
{
  options.my.features.dev.pi = {
    enable = lib.mkEnableOption "system-wide Pi API secrets template";

    provider = lib.mkOption {
      type = lib.types.str;
      default = "openrouter";
      description = "Default LLM provider (openrouter, deepseek, anthropic, etc.).";
    };

    theme = lib.mkOption {
      type = lib.types.enum [
        "dark"
        "light"
      ];
      default = "dark";
      description = "Pi UI theme.";
    };

    models = lib.mkOption {
      type = lib.types.submodule {
        options = {
          primary = lib.mkOption {
            type = lib.types.str;
            default = "google/gemini-3.7-flash";
            description = "Primary (high-capability) model for the main session and agents.";
          };
          secondary = lib.mkOption {
            type = lib.types.str;
            default = "deepseek/deepseek-v4-flash-0731";
            description = "Secondary (cost-efficient) model for subagents and lightweight tasks.";
          };
          tertiary = lib.mkOption {
            type = lib.types.str;
            default = "qwen/qwen3.7-flash";
            description = "Tertiary (ultra-cheap) model for lightweight exploration and file-gathering tasks.";
          };
        };
      };
      default = { };
      description = "Model tiers. Change here to update all agents and session defaults at once.";
    };

    thinkingLevel = lib.mkOption {
      type = lib.types.enum [
        "off"
        "minimal"
        "low"
        "medium"
        "high"
        "xhigh"
        "max"
      ];
      default = "high";
      description = "Default thinking/reasoning level.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Host-wide Pi settings override. Prefer models.* for model changes.";
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

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional Pi package paths (npm/git/local) appended to the built-in plugin set.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            package = lib.mkOption {
              type = lib.types.package;
              description = "MCP server executable package (added to the user profile for closure).";
            };
            binName = lib.mkOption {
              type = lib.types.str;
              description = "Executable name under the package's bin/ directory.";
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Arguments passed to the MCP server.";
            };
            directTools = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Register MCP tools directly instead of via the mcp proxy tool.";
            };
          };
        }
      );
      default = { };
      description = "MCP servers (pi-mcp-adapter format) written to ~/.pi/agent/mcp.json.";
    };
  };

  config = lib.mkMerge [
    {
      my.features.dev.pi.mcpServers = lib.mkDefault (
        {
          nixos = {
            package = pkgs.mcp-nixos;
            binName = "mcp-nixos";
            directTools = true;
          };
        }
        // lib.optionalAttrs (config.my.role != "server") {
          chrome-devtools = {
            package = pkgs.custom.chrome-devtools-mcp;
            binName = "chrome-devtools-mcp";
            args = [
              "--executablePath"
              "${pkgs.google-chrome}/bin/google-chrome-stable"
            ];
            directTools = true;
          };
        }
      );
    }

    (lib.mkIf (cfg.enable || cfg.providers != { }) {
      sops.templates."pi-auth.json" = lib.mkIf (cfg.providers != { }) {
        owner = config.my.user.primary or "root";
        group = "users";
        mode = "0440";
        content = builtins.toJSON (
          lib.mapAttrs (_: p: {
            type = "api_key";
            key = p.apiKey;
          }) cfg.providers
        );
      };
    })

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
            userCfg = config.my.features.dev.pi;
            mcpServers = osConfig.my.features.dev.pi.mcpServers or { };
            qualifyModel = m: if lib.hasPrefix "${cfg.provider}/" m then m else "${cfg.provider}/${m}";

            baseSettings = {
              defaultProvider = cfg.provider;
              defaultModel = cfg.models.primary;
              defaultThinkingLevel = cfg.thinkingLevel;
              theme = cfg.theme;
              enableSkillCommands = true;
              packages = lib.attrValues pluginsLib.packageDirs ++ cfg.plugins;
              subagents = {
                defaultModel = qualifyModel cfg.models.secondary;
                maxDepth = 1;
                agentOverrides = lib.mapAttrs (_: spec: {
                  model = qualifyModel cfg.models.${spec.tier};
                  thinkingLevel = spec.thinkingLevel;
                }) agentConfigs;
              };
            };
            mergedSettings = lib.recursiveUpdate (lib.recursiveUpdate baseSettings (
              osConfig.my.features.dev.pi.settings or { }
            )) userCfg.settings;
            mcpSettings = {
              mcpServers = lib.mapAttrs (_: s: {
                command = "${s.package}/bin/${s.binName}";
                args = s.args;
                directTools = s.directTools;
              }) mcpServers;
            };
          in
          {
            options.my.features.dev.pi = {
              enable = lib.mkEnableOption "Pi AI assistant for this Home Manager user";

              settings = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = "User-specific Pi settings (model, packages, mcp, etc.).";
              };

              skills = lib.mkOption {
                type = lib.types.path;
                default = piDir + "/skills";
                description = "Path to skills directory.";
              };

              agents = lib.mkOption {
                type = lib.types.path;
                default = piDir + "/agents";
                description = "Path to agents directory.";
              };
            };

            config = lib.mkIf userCfg.enable {
              # The plugin + MCP-server packages are installed into the profile so their
              # store paths (referenced as strings in settings.json/mcp.json) are
              # materialized on the target machine. `builtins.toJSON` strips string
              # context, so referencing them in the config files alone would not pull
              # them into the closure.
              home.packages = [
                pkgs.pi-coding-agent
                pkgs.nodejs
              ]
              ++ lib.attrValues pluginsLib.derivations
              ++ lib.catAttrs "package" (lib.attrValues mcpServers);

              home.file = {
                ".pi/agent/settings.json".text = builtins.toJSON mergedSettings;
                ".pi/agent/mcp.json".text = builtins.toJSON mcpSettings;
                ".pi/agent/AGENTS.md".source = piDir + "/AGENTS.md";

                ".pi/agent/skills" = {
                  source = userCfg.skills;
                  recursive = true;
                };

                ".pi/agent/agents" = {
                  source = userCfg.agents;
                  recursive = true;
                };

                ".pi/agent/auth.json" = lib.mkIf (osConfig ? sops && osConfig.sops.templates ? "pi-auth.json") {
                  source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates."pi-auth.json".path;
                };
              };
            };
          }
        )
      ];
    }
  ];
}
