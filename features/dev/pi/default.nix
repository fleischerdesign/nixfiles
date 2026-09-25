# features/dev/pi/default.nix — Generic Pi coding-agent Home-Manager & System Feature Module
#
# Architecture & Guidelines:
# - System Level: Defines provider configuration, auth.json template, settings, and MCP servers.
# - User-Scoped Level (home-manager.sharedModules): Exposes my.features.dev.pi.enable for HM users.
# - Agnostic & Generic: Zero hardcoded usernames, hostnames, or stacks. Reusable across NixOS & Home Manager.
# - Direct execution by default; delegation remains available when a bounded independent task benefits from it.
# - Provider-agnostic: provider and model identifiers are supplied by the host configuration.
# - OpenRouter routing: optional provider ordering and quantization controls when OpenRouter is used.
# - Plugins: Auto-discovered modules and packages via lib/plugins.nix.
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
in
{
  imports = (import ./lib/plugins.nix { inherit lib; }).modules;

  options.my.features.dev.pi = {
    enable = lib.mkEnableOption "Pi coding agent for enabled Home Manager users";

    provider = lib.mkOption {
      type = lib.types.str;
      default = "deepseek";
      description = "Default LLM provider (deepseek, openrouter, anthropic, openai, etc.).";
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "deepseek-flash";
      description = "Optional default model identifier override.";
    };

    openRouterRouting = lib.mkOption {
      type = lib.types.submodule {
        options = {
          order = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "Wafer"
              "Fireworks"
              "DeepInfra"
            ];
            description = "Ordered provider preference for OpenRouter.";
          };
          ignore = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "Baidu" ];
            description = "Explicit list of providers to exclude from routing.";
          };
          quantizations = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Allowed quantizations (e.g. ['fp8'], ['fp8' 'bf16']).";
          };
          allowFallbacks = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Allow fallback providers satisfying quantization criteria.";
          };
        };
      };
      default = { };
      description = "OpenRouter-specific routing rules.";
    };

    theme = lib.mkOption {
      type = lib.types.str;
      default = "dark";
      description = "Pi UI theme name or path.";
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
      default = "low";
      description = "Default thinking/reasoning level.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Host-wide Pi settings override.";
    };

    customProviders = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Custom provider definitions injected into models.json (e.g. self-hosted Ollama, vLLM).";
    };

    cliPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        ripgrep
        fd
        jq
      ];
      description = "CLI packages available to Pi through the user's PATH.";
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

    plugins = {
      extraPlugins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional Pi package paths (npm/git/local) appended to the built-in plugin set.";
      };
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
            directTools = false;
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
            directTools = false;
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
            activeMcpServers = lib.optionalAttrs cfg.plugins.pi-mcp-adapter.enable mcpServers;

            activePluginNames = lib.filter (name: cfg.plugins.${name}.enable or false) (
              lib.attrNames pluginsLib.packageDirs
            );
            activePluginDirs = map (name: pluginsLib.packageDirs.${name}) activePluginNames;
            activePluginDerivations = map (name: pluginsLib.derivations.${name}) activePluginNames;

            baseSettings = {
              defaultProvider = cfg.provider;
              defaultThinkingLevel = cfg.thinkingLevel;
              quietStartup = true;
              theme = cfg.theme;
              enableSkillCommands = true;
              packages = activePluginDirs ++ cfg.plugins.extraPlugins;
            }
            // lib.optionalAttrs (cfg.defaultModel != null) {
              defaultModel = cfg.defaultModel;
            };

            mergedSettings = lib.recursiveUpdate (lib.recursiveUpdate baseSettings (
              osConfig.my.features.dev.pi.settings or { }
            )) userCfg.settings;

            mcpAdapterCfg = cfg.plugins.pi-mcp-adapter;
            mcpAdapterSettings = {
              inherit (mcpAdapterCfg) mcpFooterStatus disableProxyTool;
            }
            // mcpAdapterCfg.extraConfig;

            mcpSettings = {
              settings = mcpAdapterSettings;
              mcpServers = lib.mapAttrs (_: s: {
                command = "${s.package}/bin/${s.binName}";
                args = s.args;
                directTools = s.directTools;
              }) activeMcpServers;
            };

            openRouterOverrides =
              lib.optionalAttrs (cfg.provider == "openrouter" || cfg.providers ? openrouter)
                {
                  openrouter = {
                    compat = {
                      openRouterRouting = {
                        allow_fallbacks = cfg.openRouterRouting.allowFallbacks;
                        quantizations = cfg.openRouterRouting.quantizations;
                      }
                      // lib.optionalAttrs (cfg.openRouterRouting.order != [ ]) {
                        inherit (cfg.openRouterRouting) order;
                      }
                      // lib.optionalAttrs (cfg.openRouterRouting.ignore != [ ]) {
                        inherit (cfg.openRouterRouting) ignore;
                      };
                    };
                  };
                };

            modelsJsonContent = {
              providers = lib.recursiveUpdate openRouterOverrides cfg.customProviders;
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

              themes = lib.mkOption {
                type = lib.types.path;
                default = piDir + "/themes";
                description = "Path to themes directory.";
              };
            };

            config = lib.mkIf userCfg.enable {
              # The plugin + MCP-server packages are installed into the profile so their
              # store paths (referenced as strings in settings.json/mcp.json) are
              # materialized on the target machine. Keep derivation references in the
              # generated values so Nix retains their string context in the closure.
              home.sessionVariables = {
                PI_BG_DISABLE_UPDATE_CHECK = "1";
              };

              home.packages = [
                pkgs.pi-coding-agent
                pkgs.nodejs
              ]
              ++ cfg.cliPackages
              ++ activePluginDerivations
              ++ lib.catAttrs "package" (lib.attrValues activeMcpServers);

              home.file = lib.mkMerge [
                {
                  ".pi/agent/settings.json".text = builtins.toJSON mergedSettings;
                  ".pi/agent/mcp.json".text = builtins.toJSON mcpSettings;
                  ".pi/agent/AGENTS.md".source = piDir + "/AGENTS.md";
                  ".pi/agent/skills" = {
                    source = userCfg.skills;
                    recursive = true;
                  };

                  ".pi/agent/themes" = {
                    source = userCfg.themes;
                    recursive = true;
                  };

                  ".pi/agent/auth.json" = lib.mkIf (osConfig ? sops && osConfig.sops.templates ? "pi-auth.json") {
                    source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates."pi-auth.json".path;
                  };
                }
                (lib.optionalAttrs (modelsJsonContent.providers != { }) {
                  ".pi/agent/models.json".text = builtins.toJSON modelsJsonContent;
                })
              ];
            };
          }
        )
      ];
    }
  ];
}
