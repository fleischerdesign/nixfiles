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
      description = "Focused implementation agent. Write code from specifications and architectural designs with TDD discipline. Narrow scope, evidence-driven, no scope creep.";
    };
    review = {
      tier = "primary";
      thinkingLevel = "medium";
      description = "Independent code reviewer with fresh context — unbiased, evidence-based, structured findings";
    };
    security-reviewer = {
      tier = "primary";
      thinkingLevel = "high";
      description = "Independent security reviewer with fresh context — adversary-perspective analysis, STRIDE threat modeling, zero trust in developer assumptions";
    };
    explore = {
      tier = "tertiary";
      thinkingLevel = "low";
      fallbackTier = "secondary";
      description = "Ultra-fast repository exploration and information gathering agent. Reads files, lists directories, and gathers code context.";
    };
    vision = {
      tier = "vision";
      thinkingLevel = "low";
      fallbackModel = "google/gemini-3.7-flash";
      description = "Specialized visual and multimodal analysis agent. Inspects images, screenshots, diagrams, UI mockups, and visual artifacts to extract precise structured observations, text (OCR), layout details, and anomalies.";
    };
  };

  modelSubmodule = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Model identifier (e.g. 'deepseek/deepseek-v4-flash-0731' or 'deepseek-chat').";
      };

      provider = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Provider override for this tier (defaults to cfg.provider if null).";
      };

      routing = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              order = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Ordered provider preference for OpenRouter.";
              };
              ignore = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Explicit list of providers to exclude from routing (e.g. ['Baidu']).";
              };
              quantizations = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "fp8" ];
                description = "Allowed quantizations (e.g. ['fp8'], ['fp8' 'bf16']).";
              };
              allowFallbacks = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Allow fallback providers satisfying quantization criteria.";
              };
            };
          }
        );
        default = null;
        description = "OpenRouter-specific routing rules for this model.";
      };
    };
  };

  modelType = lib.types.coercedTo lib.types.str (id: { inherit id; }) modelSubmodule;
in
{
  options.my.features.dev.pi = {
    enable = lib.mkEnableOption "system-wide Pi API secrets template";

    provider = lib.mkOption {
      type = lib.types.str;
      default = "openrouter";
      description = "Default LLM provider (openrouter, deepseek, anthropic, openai, etc.).";
    };

    theme = lib.mkOption {
      type = lib.types.str;
      default = "dark";
      description = "Pi UI theme name or path.";
    };

    models = lib.mkOption {
      type = lib.types.submodule {
        options = {
          primary = lib.mkOption {
            type = modelType;
            default = {
              id = "deepseek/deepseek-v4-flash-0731";
              routing = {
                order = [
                  "DeepInfra"
                  "StreamLake"
                  "Novita"
                ];
                ignore = [ "Baidu" ];
                quantizations = [ "fp8" ];
                allowFallbacks = true;
              };
            };
            description = "Primary model for the main session and review agents.";
          };
          secondary = lib.mkOption {
            type = modelType;
            default = {
              id = "deepseek/deepseek-v4-flash-0731";
              routing = {
                order = [
                  "Baidu"
                  "DeepInfra"
                  "StreamLake"
                  "Novita"
                ];
                quantizations = [ "fp8" ];
                allowFallbacks = true;
              };
            };
            description = "Secondary model for implementation subagents.";
          };
          tertiary = lib.mkOption {
            type = modelType;
            default = "qwen/qwen3.7-flash";
            description = "Tertiary model for lightweight exploration tasks.";
          };
          vision = lib.mkOption {
            type = modelType;
            default = "xiaomi/mimo-v2.5";
            description = "Multimodal vision model for visual asset analysis.";
          };
        };
      };
      default = { };
      description = "Model tiers. Easily switchable globally or per model tier.";
    };

    customProviders = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Custom provider definitions injected into models.json (e.g. self-hosted Ollama, vLLM).";
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
      default = "medium";
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

    plugins = {
      mcp-adapter = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Model Context Protocol (MCP) adapter plugin.";
        };
        config = lib.mkOption {
          type = lib.types.submodule {
            options = {
              mcpFooterStatus = lib.mkOption {
                type = lib.types.enum [
                  "full"
                  "compact"
                  "off"
                ];
                default = "off";
                description = "Footer status indicator mode for pi-mcp-adapter.";
              };
              disableProxyTool = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Hide the mcp proxy tool once direct tools are resolved.";
              };
            };
          };
          default = { };
          description = "Native JSON configuration payload for pi-mcp-adapter.";
        };
      };

      subagents = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable pi-subagents execution engine plugin.";
        };
        config = lib.mkOption {
          type = lib.types.submodule {
            options = {
              maxDepth = lib.mkOption {
                type = lib.types.int;
                default = 1;
                description = "Maximum subagent recursion depth.";
              };
            };
          };
          default = { };
          description = "Native JSON configuration payload for pi-subagents.";
        };
      };

      context-mode = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable context trimming & summarization plugin.";
        };
        config = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Native configuration payload for context-mode.";
        };
      };

      web-access = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable web fetch & search capabilities plugin.";
        };
        config = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Native configuration payload for web-access.";
        };
      };

      rpiv-todo = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable persistent task-tree management plugin.";
        };
        config = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Native configuration payload for rpiv-todo.";
        };
      };

      pi-background-tasks = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable durable background shell tasks & async process management plugin.";
        };
        enableFusion = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable multi-model Fusion consensus tools (fusion_investigate, fusion_reason, etc.). Default is false to keep tool surface clean.";
        };
        config = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Native configuration payload for pi-background-tasks.";
        };
      };

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
          let
            openRouterAliases = lib.genAttrs [
              "openrouter-secondary"
              "openrouter-tertiary"
              "openrouter-vision"
            ] (_: cfg.providers.openrouter);
            allProviders = cfg.providers // lib.optionalAttrs (cfg.providers ? openrouter) openRouterAliases;
          in
          lib.mapAttrs (_: p: {
            type = "api_key";
            key = p.apiKey;
          }) allProviders
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
            getModelId = m: if builtins.isAttrs m then m.id else m;
            getRawProvider =
              m: if builtins.isAttrs m && (m.provider or null != null) then m.provider else cfg.provider;

            primaryRouting =
              if builtins.isAttrs cfg.models.primary then cfg.models.primary.routing or null else null;

            # Check if a non-primary tier requires a dedicated virtual openrouter provider
            tierNeedsVirtualOpenRouter =
              tierName:
              if !(cfg.models ? ${tierName}) then
                false
              else
                let
                  tierSpec = cfg.models.${tierName};
                  tierProv = getRawProvider tierSpec;
                  tierRouting = if builtins.isAttrs tierSpec then tierSpec.routing or null else null;
                in
                tierName != "primary"
                && tierProv == "openrouter"
                && tierRouting != null
                && tierRouting != primaryRouting;

            getTierProvider =
              tierName: m:
              if tierNeedsVirtualOpenRouter tierName then "openrouter-${tierName}" else getRawProvider m;

            qualifyModel =
              tierName: m:
              let
                id = getModelId m;
                prov = getTierProvider tierName m;
                rawProv = getRawProvider m;
                cleanId = lib.removePrefix "${rawProv}/" id;
              in
              "${prov}/${cleanId}";

            activePluginNames = lib.filter (name: cfg.plugins.${name}.enable or true) (
              lib.attrNames pluginsLib.packageDirs
            );
            activePluginDirs = map (name: pluginsLib.packageDirs.${name}) activePluginNames;

            fusionTools = [
              "fusion_investigate"
              "fusion_reason"
              "fusion_research"
              "fusion_validate"
            ];

            openRouterOverrides =
              let
                primaryId = lib.removePrefix "openrouter/" (getModelId cfg.models.primary);
              in
              lib.optionalAttrs (getRawProvider cfg.models.primary == "openrouter" && primaryRouting != null) {
                ${primaryId} = {
                  compat = {
                    openRouterRouting = {
                      allow_fallbacks = primaryRouting.allowFallbacks;
                    }
                    // lib.optionalAttrs (primaryRouting.order != [ ]) { inherit (primaryRouting) order; }
                    // lib.optionalAttrs (primaryRouting.ignore != [ ]) { inherit (primaryRouting) ignore; }
                    // lib.optionalAttrs (primaryRouting.quantizations != [ ]) {
                      inherit (primaryRouting) quantizations;
                    };
                  };
                };
              };

            virtualTierProviders = lib.listToAttrs (
              lib.concatMap
                (
                  tierName:
                  let
                    tierSpec = cfg.models.${tierName};
                    routing = tierSpec.routing or null;
                    cleanId = lib.removePrefix "openrouter/" (getModelId tierSpec);
                  in
                  lib.optional (tierNeedsVirtualOpenRouter tierName) {
                    name = "openrouter-${tierName}";
                    value = {
                      name = "OpenRouter (${tierName})";
                      baseUrl = "https://openrouter.ai/api/v1";
                      api = "openai-completions";
                      compat = {
                        openRouterRouting = {
                          allow_fallbacks = routing.allowFallbacks;
                        }
                        // lib.optionalAttrs (routing.order != [ ]) { inherit (routing) order; }
                        // lib.optionalAttrs (routing.ignore != [ ]) { inherit (routing) ignore; }
                        // lib.optionalAttrs (routing.quantizations != [ ]) {
                          inherit (routing) quantizations;
                        };
                      };
                      models = [
                        {
                          id = cleanId;
                          name = "${cleanId} (${tierName})";
                          api = "openai-completions";
                        }
                      ];
                    };
                  }
                )
                [
                  "secondary"
                  "tertiary"
                  "vision"
                ]
            );

            modelsJsonContent = {
              providers = lib.recursiveUpdate (lib.recursiveUpdate (lib.optionalAttrs (openRouterOverrides != { })
                {
                  openrouter = {
                    modelOverrides = openRouterOverrides;
                  };
                }
              ) virtualTierProviders) cfg.customProviders;
            };

            baseSettings = {
              defaultProvider = cfg.provider;
              defaultModel = getModelId cfg.models.primary;
              defaultThinkingLevel = cfg.thinkingLevel;
              quietStartup = true;
              theme = cfg.theme;
              enableSkillCommands = true;
              packages = activePluginDirs ++ cfg.plugins.extraPlugins;
              excludeTools = lib.optionals (!cfg.plugins.pi-background-tasks.enableFusion) fusionTools;
              subagents = lib.optionalAttrs cfg.plugins.subagents.enable {
                disableBuiltins = true;
                defaultModel = qualifyModel "secondary" cfg.models.secondary;
                maxDepth = cfg.plugins.subagents.config.maxDepth;
                modelScope = {
                  enforce = true;
                  strict = true;
                  allow = lib.unique [
                    (qualifyModel "primary" cfg.models.primary)
                    (qualifyModel "secondary" cfg.models.secondary)
                    (qualifyModel "tertiary" cfg.models.tertiary)
                    (qualifyModel "vision" cfg.models.vision)
                    (qualifyModel "fallback" "google/gemini-3.7-flash")
                  ];
                };
                agentOverrides = lib.mapAttrs (_: spec: {
                  model = qualifyModel spec.tier cfg.models.${spec.tier};
                  thinkingLevel = spec.thinkingLevel;
                }) agentConfigs;
              };
            };
            mergedSettings = lib.recursiveUpdate (lib.recursiveUpdate baseSettings (
              osConfig.my.features.dev.pi.settings or { }
            )) userCfg.settings;
            mcpSettings = {
              settings = cfg.plugins.mcp-adapter.config;
              mcpServers = lib.mapAttrs (_: s: {
                command = "${s.package}/bin/${s.binName}";
                args = s.args;
                directTools = s.directTools;
              }) mcpServers;
            };

            # Dynamically inject model & thinking fields into agent markdown files
            mkAgentFileText =
              name:
              let
                spec =
                  agentConfigs.${name} or {
                    tier = "secondary";
                    thinkingLevel = "low";
                  };
                modelStr = qualifyModel spec.tier cfg.models.${spec.tier};
                thinkingStr = spec.thinkingLevel;
                rawContent = builtins.readFile (piDir + "/agents/${name}.md");
                # Remove existing top-level YAML frontmatter if present
                lines = lib.splitString "\n" rawContent;
                hasFrontmatter = lib.length lines > 1 && (lib.elemAt lines 0) == "---";
                tailLines =
                  if hasFrontmatter then
                    let
                      rest = lib.drop 1 lines;
                      idx = lib.lists.findFirstIndex (x: x == "---") null rest;
                    in
                    if idx != null then lib.drop (idx + 1) rest else lines
                  else
                    lines;
                bodyText = lib.concatStringsSep "\n" tailLines;
                fallbackLine =
                  if spec ? fallbackTier then
                    "fallbackModels:\n  - ${qualifyModel spec.fallbackTier cfg.models.${spec.fallbackTier}}\n"
                  else if spec ? fallbackModel then
                    "fallbackModels:\n  - ${qualifyModel "fallback" spec.fallbackModel}\n"
                  else
                    "";
              in
              ''
                ---
                name: ${name}
                description: ${spec.description}
                model: ${modelStr}
                thinking: ${thinkingStr}
                ${fallbackLine}---
                ${bodyText}
              '';
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

              themes = lib.mkOption {
                type = lib.types.path;
                default = piDir + "/themes";
                description = "Path to themes directory.";
              };
            };

            config = lib.mkIf userCfg.enable {
              # The plugin + MCP-server packages are installed into the profile so their
              # store paths (referenced as strings in settings.json/mcp.json) are
              # materialized on the target machine. `builtins.toJSON` strips string
              # context, so referencing them in the config files alone would not pull
              # them into the closure.
              home.sessionVariables = {
                PI_BG_DISABLE_UPDATE_CHECK = "1";
              };

              home.packages = [
                pkgs.pi-coding-agent
                pkgs.nodejs
              ]
              ++ lib.attrValues pluginsLib.derivations
              ++ lib.catAttrs "package" (lib.attrValues mcpServers);

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
                (lib.mapAttrs' (
                  name: _:
                  lib.nameValuePair ".pi/agent/agents/${name}.md" {
                    text = mkAgentFileText name;
                  }
                ) agentConfigs)
              ];
            };
          }
        )
      ];
    }
  ];
}
