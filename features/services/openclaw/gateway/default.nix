# features/services/openclaw/gateway/default.nix
# OpenClaw multi-tenant gateway service.
# Each instance runs an isolated gateway daemon with its own port, state directory,
# configuration file, database, log file, and separate trust boundary (secrets, GitHub PAT, etc.).
#
# Instances are exposed via Caddy and Authentik forward-auth as:
#   <subdomain>.<baseDomain> (e.g. philipp.ai.rls.ancoris.ovh)
{
  lib,
  pkgs,
  ...
}@topArgs:
let
  osConfig = topArgs.config;
  cfg = osConfig.my.features.services.openclaw.gateway;

  # Submodule schema for a single gateway instance
  instanceSubmodule =
    { name, config, ... }:
    let
      inst = config;

      # Central endpoint registry key for this instance
      endpointName = "openclaw-${name}";

      # SSOT for public URL
      publicUrl =
        if inst.subdomain != null && inst.subdomain != "" then
          "https://${inst.subdomain}.${inst.domain}"
        else
          "https://${inst.domain}";

      remoteUrl = lib.replaceStrings [ "https://" ] [ "wss://" ] publicUrl;

      secretEnv =
        envVar: secretName:
        lib.optionalString (secretName != null) "${envVar}=${osConfig.sops.placeholder.${secretName}}";

      secretEnvLines = lib.filter (line: line != "") [
        (secretEnv "DEEPSEEK_API_KEY" inst.secrets.deepseek)
        (secretEnv "OPENAI_API_KEY" inst.secrets.openai)
        (secretEnv "OPENCLAW_GATEWAY_PASSWORD" inst.secrets.password)
        (secretEnv "GITHUB_TOKEN" inst.secrets.github)
        (secretEnv "GH_TOKEN" inst.secrets.github)
        (secretEnv "A2A_TOKEN" (lib.optionalString inst.a2a.enable inst.a2a.tokenSecret))
      ];

      secretNames = lib.filter (s: s != null && s != "") (
        [
          inst.secrets.deepseek
          inst.secrets.openai
          inst.secrets.password
          inst.secrets.github
          (lib.optionalString inst.a2a.enable inst.a2a.tokenSecret)
        ]
        ++ lib.optionals inst.a2a.enable (lib.mapAttrsToList (_: p: p.tokenSecret) inst.a2a.peers)
      );

      a2aConfig = lib.optionalAttrs inst.a2a.enable {
        channels.a2a = {
          enabled = true;
          advertisedUrl = inst.a2a.advertisedUrl;
          peers = builtins.mapAttrs (_peerName: peer: {
            url =
              let
                trimmed = lib.removeSuffix "/" peer.url;
              in
              if lib.hasSuffix "/a2a/v1" trimmed then trimmed else "${trimmed}/a2a/v1";
            token =
              if peer.tokenSecret != null then
                osConfig.sops.placeholder.${peer.tokenSecret}
              else
                osConfig.sops.placeholder.${inst.a2a.tokenSecret};
            outboundToken =
              if inst.a2a.tokenSecret != null then
                osConfig.sops.placeholder.${inst.a2a.tokenSecret}
              else
                osConfig.sops.placeholder.${peer.tokenSecret};
          }) inst.a2a.peers;
        };
      };

      hasSecrets = secretNames != [ ];

      effectiveRuntimePlugins = lib.unique (inst.plugins.runtime ++ inst.runtimePlugins);

      unknownPlugins = lib.filter (
        id: !(builtins.hasAttr id pkgs.openclawRuntimePlugins)
      ) effectiveRuntimePlugins;

      activeMemoryConfig = lib.optionalAttrs inst.plugins.activeMemory.enable {
        "active-memory" = {
          enabled = true;
          config = {
            enabled = true;
            mode = inst.plugins.activeMemory.mode;
            queryMode = inst.plugins.activeMemory.queryMode;
            promptStyle = inst.plugins.activeMemory.promptStyle;
            timeoutMs = inst.plugins.activeMemory.timeoutMs;
            maxSummaryChars = inst.plugins.activeMemory.maxSummaryChars;
            persistTranscripts = inst.plugins.activeMemory.persistTranscripts;
            logging = inst.plugins.activeMemory.logging;
          }
          // lib.optionalAttrs (inst.plugins.activeMemory.agents != [ ]) {
            agents = inst.plugins.activeMemory.agents;
          }
          // lib.optionalAttrs (inst.plugins.activeMemory.model != null) {
            model = inst.plugins.activeMemory.model;
          }
          // lib.optionalAttrs (inst.plugins.activeMemory.modelFallback != null) {
            modelFallback = inst.plugins.activeMemory.modelFallback;
          };
        };
      };

      workboardConfig = lib.optionalAttrs inst.plugins.workboard.enable {
        workboard.enabled = true;
      };

      runtimePluginEntries = lib.genAttrs effectiveRuntimePlugins (_: {
        enabled = true;
      });

      extraPluginEntries = builtins.mapAttrs (_: entry: {
        inherit (entry) enabled;
        config = entry.config;
      }) inst.plugins.extraEntries;

      pluginConfig = {
        plugins = {
          load.paths = map (id: "${pkgs.openclawRuntimePlugins.${id}}") effectiveRuntimePlugins;
          entries = runtimePluginEntries // workboardConfig // activeMemoryConfig // extraPluginEntries;
        };
      };

      stateDir = "/var/lib/openclaw/instances/${name}";
      configPath = "/etc/openclaw/instances/${name}.json";
      logPath = "${stateDir}/logs/gateway.log";

      renderedConfig = lib.recursiveUpdate (
        {
          gateway = {
            port = inst.port;
            mode = "local";
            bind = "lan";
            remote.url = remoteUrl;
            trustedProxies = [
              "127.0.0.1"
              "::1"
            ];
            auth = {
              mode = "trusted-proxy";
              identityScopes = lib.genAttrs inst.adminUsers (_: [ "operator.admin" ]);
              trustedProxy = {
                userHeader = "x-authentik-email";
                requiredHeaders = [ "x-authentik-email" ];
                allowLoopback = true;
                deviceAutoApprove = {
                  enabled = true;
                  scopes = [
                    "operator.read"
                    "operator.write"
                    "operator.approvals"
                    "operator.questions"
                  ];
                };
              };
            };
            controlUi = {
              enabled = true;
              allowedOrigins = [ publicUrl ] ++ inst.controlUiExtraOrigins;
            }
            // lib.optionalAttrs (inst.secrets.github != null) {
              github.token = "$GITHUB_TOKEN";
            };
            nodes.pairing = {
              autoApproveLocal = true;
            }
            // lib.optionalAttrs (inst.autoApproveCidrs != [ ]) {
              autoApproveCidrs = inst.autoApproveCidrs;
            };
          };
          models.mode = "merge";
          memory.search.provider = inst.memorySearch;
          agents.defaults.model.primary = inst.defaultModel;
          talk = {
            speechLocale = "de-DE";
            realtime = {
              instructions = "Antworte immer auf Deutsch.";
            };
          };
        }
        // pluginConfig
        // a2aConfig
      ) inst.settings;
    in
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable this gateway instance.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          description = "Internal loopback port for this gateway instance.";
        };

        subdomain = lib.mkOption {
          type = lib.types.str;
          description = "Subdomain below baseDomain, e.g. philipp.ai -> philipp.ai.<baseDomain>.";
        };

        domain = lib.mkOption {
          type = lib.types.str;
          default = osConfig.my.features.services.caddy.baseDomain or "";
          description = "Base domain for reverse proxy.";
        };

        auth = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Protect with Authentik forward-auth.";
        };

        adminUsers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Authentik emails granted operator.admin scopes on this gateway instance.";
        };

        defaultModel = lib.mkOption {
          type = lib.types.str;
          default = "deepseek/deepseek-flash";
          description = "Default agent model for this instance.";
        };

        memorySearch = lib.mkOption {
          type = lib.types.enum [
            "openai"
            "local"
          ];
          default = "openai";
          description = "Embedding provider for memory search.";
        };

        plugins = {
          runtime = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "External runtime plugins loaded from pkgs.openclawRuntimePlugins (e.g. deepseek).";
          };

          workboard = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable Workboard task and kanban management plugin.";
            };
          };

          activeMemory = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable Active Memory bounded pre-reply retrieval across conversations.";
            };

            mode = lib.mkOption {
              type = lib.types.enum [
                "escalate"
                "always"
                "off"
              ];
              default = "escalate";
              description = "Recall mode: escalate deep recall only for recall intent, or always.";
            };

            agents = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Target agent IDs. Empty list targets all eligible agents.";
            };

            model = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Dedicated provider/model for the blocking memory sub-agent.";
            };

            modelFallback = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Fallback provider/model if no session or primary agent model resolves.";
            };

            queryMode = lib.mkOption {
              type = lib.types.enum [
                "message"
                "recent"
                "full"
              ];
              default = "recent";
              description = "Context seen by memory sub-agent: latest message, recent tail, or full.";
            };

            promptStyle = lib.mkOption {
              type = lib.types.enum [
                "eager"
                "balanced"
                "strict"
              ];
              default = "balanced";
              description = "How eager or strict the blocking memory sub-agent is.";
            };

            timeoutMs = lib.mkOption {
              type = lib.types.int;
              default = 15000;
              description = "Recall work budget in milliseconds.";
            };

            maxSummaryChars = lib.mkOption {
              type = lib.types.int;
              default = 220;
              description = "Maximum total characters allowed in the active-memory summary.";
            };

            persistTranscripts = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Persist blocking sub-agent transcripts on disk.";
            };

            logging = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable Active Memory diagnostic logging.";
            };
          };

          extraEntries = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  enabled = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Whether this plugin entry is enabled.";
                  };
                  config = lib.mkOption {
                    type = lib.types.attrs;
                    default = { };
                    description = "Plugin configuration passed to plugins.entries.<id>.config.";
                  };
                };
              }
            );
            default = { };
            description = "Arbitrary plugin configurations passed directly into plugins.entries.";
          };
        };

        # Backwards compatibility alias for runtimePlugins
        runtimePlugins = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Legacy alias for plugins.runtime.";
        };

        controlUiExtraOrigins = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra allowed origins for Control UI.";
        };

        autoApproveCidrs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = osConfig.my.features.system.networking.topology.trustedSubnets or [ ];
          description = "CIDR ranges from which node pairings are auto-approved.";
        };

        openTailscaleFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open instance port on Tailscale firewall interface.";
        };

        gitAuthor = {
          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Git author and committer name for workspace sync and commits.";
          };

          email = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Git author and committer email for workspace sync and commits.";
          };
        };

        secrets = {
          deepseek = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "SOPS secret for DEEPSEEK_API_KEY.";
          };

          openai = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "SOPS secret for OPENAI_API_KEY.";
          };

          password = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "SOPS secret for OPENCLAW_GATEWAY_PASSWORD.";
          };

          github = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "SOPS secret for GITHUB_TOKEN and GH_TOKEN.";
          };
        };

        extraEnvironmentFiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra systemd EnvironmentFiles.";
        };

        a2a = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable A2A (Agent-to-Agent) protocol channel.";
          };

          advertisedUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = publicUrl;
            description = "Public gateway origin advertised in agent card.";
          };

          tokenSecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "openclaw_gateway_token";
            description = "SOPS secret used for A2A peer authentication.";
          };

          peers = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  url = lib.mkOption {
                    type = lib.types.str;
                    description = "Target peer URL (e.g. https://katja.ai.rls.ancoris.ovh).";
                  };
                  tokenSecret = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = "openclaw_gateway_token";
                    description = "SOPS secret containing bearer token for this peer.";
                  };
                };
              }
            );
            default = { };
            description = "Declared A2A peer gateways.";
          };
        };

        settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Arbitrary openclaw.json overrides merged into this instance.";
        };

        # Computed internal attributes
        _stateDir = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = stateDir;
        };

        _configPath = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = configPath;
        };

        _logPath = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = logPath;
        };

        _hasSecrets = lib.mkOption {
          type = lib.types.bool;
          internal = true;
          default = hasSecrets;
        };

        _secretNames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          default = secretNames;
        };

        _secretEnvLines = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          default = secretEnvLines;
        };

        _unknownPlugins = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          default = unknownPlugins;
        };

        _renderedConfig = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          default = renderedConfig;
        };

        _endpointName = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = endpointName;
        };
      };
    };

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) cfg.instances;
in
{
  options.my.features.services.openclaw.gateway = {
    enable = lib.mkEnableOption "OpenClaw multi-tenant gateway service";

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceSubmodule);
      default = { };
      description = "Declared OpenClaw gateway instances.";
    };
  };

  config = lib.mkIf (cfg.enable && enabledInstances != { }) {
    # Validate plugins on all enabled instances
    assertions = lib.concatMap (
      name:
      let
        inst = enabledInstances.${name};
      in
      [
        {
          assertion = inst._unknownPlugins == [ ];
          message = "OpenClaw gateway instance '${name}' has unknown runtimePlugins: ${lib.concatStringsSep ", " inst._unknownPlugins}";
        }
      ]
    ) (lib.attrNames enabledInstances);

    # Ensure openclaw group and system user exist
    users.groups.openclaw = { };
    users.users.openclaw = {
      isSystemUser = true;
      group = "openclaw";
      home = "/var/lib/openclaw";
      createHome = true;
      shell = pkgs.bashInteractive;
    };

    # Collect all secrets used across all instances
    sops.secrets = lib.genAttrs (lib.unique (
      lib.concatMap (inst: inst._secretNames) (lib.attrValues enabledInstances)
    )) (_: { });

    # Generate one environment file and one config file per instance via sops.templates
    # This ensures placeholders like openclaw_gateway_token in JSON are dynamically expanded without leaking into nix store.
    sops.templates = lib.listToAttrs (
      lib.concatMap (
        name:
        let
          inst = enabledInstances.${name};
          rawJson = builtins.toJSON inst._renderedConfig;
        in
        [
          {
            name = "openclaw_${name}_config";
            value = {
              owner = "openclaw";
              group = "openclaw";
              mode = "0640";
              restartUnits = [ "openclaw-gateway-${name}.service" ];
              content = rawJson;
            };
          }
        ]
        ++ lib.optional inst._hasSecrets {
          name = "openclaw_${name}_env";
          value = {
            owner = "openclaw";
            group = "openclaw";
            mode = "0640";
            restartUnits = [ "openclaw-gateway-${name}.service" ];
            content = lib.concatLines inst._secretEnvLines;
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    # Directory permissions for instances
    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw 0750 openclaw openclaw - -"
      "d /var/lib/openclaw/instances 0750 openclaw openclaw - -"
    ]
    ++ lib.concatMap (
      name:
      let
        inst = enabledInstances.${name};
      in
      [
        "d ${inst._stateDir} 0750 openclaw openclaw - -"
        "d ${builtins.dirOf inst._logPath} 0750 openclaw openclaw - -"
      ]
    ) (lib.attrNames enabledInstances);

    # Generate isolated systemd units for each instance
    systemd.services = lib.listToAttrs (
      map (
        name:
        let
          inst = enabledInstances.${name};
          openclawPkg = pkgs.openclaw;
          instanceConfigPath = osConfig.sops.templates."openclaw_${name}_config".path;
        in
        {
          name = "openclaw-gateway-${name}";
          value = {
            description = "OpenClaw gateway instance (${name})";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            environment = {
              OPENCLAW_CONFIG_PATH = instanceConfigPath;
              OPENCLAW_STATE_DIR = inst._stateDir;
              CLAWDBOT_CONFIG_PATH = instanceConfigPath;
              CLAWDBOT_STATE_DIR = inst._stateDir;
              OPENCLAW_NIX_MODE = "1";
              OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY = "1";
            }
            // lib.optionalAttrs (inst.gitAuthor.name != null) {
              GIT_AUTHOR_NAME = inst.gitAuthor.name;
              GIT_COMMITTER_NAME = inst.gitAuthor.name;
            }
            // lib.optionalAttrs (inst.gitAuthor.email != null) {
              GIT_AUTHOR_EMAIL = inst.gitAuthor.email;
              GIT_COMMITTER_EMAIL = inst.gitAuthor.email;
            };

            serviceConfig = {
              User = "openclaw";
              Group = "openclaw";
              WorkingDirectory = inst._stateDir;
              EnvironmentFile =
                lib.optional inst._hasSecrets osConfig.sops.templates."openclaw_${name}_env".path
                ++ inst.extraEnvironmentFiles;
              ExecStart = "${openclawPkg}/bin/openclaw gateway --port ${toString inst.port}";
              Restart = "always";
              RestartSec = 2;
              StandardOutput = "append:${inst._logPath}";
              StandardError = "append:${inst._logPath}";
            };

            path = [
              pkgs.bash
              pkgs.coreutils
              pkgs.procps
              pkgs.git
              pkgs.gh
            ];
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    # Register each instance into the central endpoint registry for Caddy and Firewall
    my.endpoints = lib.listToAttrs (
      map (
        name:
        let
          inst = enabledInstances.${name};
        in
        {
          name = inst._endpointName;
          value = {
            host = osConfig.networking.hostName;
            port = inst.port;
            directAccess = {
              enable = inst.openTailscaleFirewall;
              protocol = "tcp";
              interface = "tailscale";
            };
            proxy = {
              enable = true;
              subdomain = inst.subdomain;
              domain = inst.domain;
              auth = inst.auth;
              unauthenticatedPaths = [
                "/j/*"
                "/__openclaw__/worker*"
                "/.well-known/agent-card.json"
                "/.well-known/agent.json"
                "/a2a/*"
              ];
              machineClientsBypassAuth = true;
            };
            monitoring = {
              http.enable = false;
              tcp = {
                enable = true;
                group = "AI";
              };
            };
          };
        }
      ) (lib.attrNames enabledInstances)
    );
  };
}
