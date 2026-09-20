# features/services/openclaw/gateway/default.nix
# OpenClaw multi-tenant gateway service.
# Each instance runs an isolated gateway daemon with its own port, state directory,
# configuration file, database, log file, and separate trust boundary (secrets, GitHub PAT, etc.).
#
# Instances are exposed via Caddy and Authentik forward-auth as:
#   https://<subdomain>.<domain> (e.g. https://philipp.ai.vyrx.de)
{
  lib,
  pkgs,
  ...
}@topArgs:
let
  osConfig = topArgs.config;
  cfg = osConfig.my.features.services.openclaw.gateway;

  # The public ingress (Caddy + Authentik forward-auth) is the only legitimate proxy in front
  # of a gateway, so its overlay address is the only non-loopback entry allowed in
  # gateway.trustedProxies. Derived from the topology, so a new ingress host needs no edit
  # here (docs/architecture.md §7.1). OpenClaw validates the source address of proxy-shaped traffic
  # and rejects untrusted ones with `proxy_attribution_required`.
  ingressProxyAddress =
    (osConfig.my.topology.hosts.${osConfig.my.topology.ingressHost} or { }).wireguardIpv4 or null;

  # Standard baseline toolchain available to OpenClaw execution environments
  defaultBasePackages = [
    pkgs.nix
    pkgs.git
    pkgs.gh
    pkgs.ripgrep
    pkgs.ripgrep-all
    pkgs.fd
    pkgs.procps
    pkgs.curl
    pkgs.gnutar
    pkgs.gzip
    pkgs.zip
    pkgs.unzip
    pkgs.jq
    pkgs.yq-go
    pkgs.sqlite
    pkgs.poppler-utils
    pkgs.imagemagick
    pkgs.pandoc
    pkgs.ast-grep
    pkgs.universal-ctags
    pkgs.tokei
    pkgs.lsof
    pkgs.moreutils
    pkgs.nvd
    pkgs.nix-diff
  ];

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
          (lib.optionalString inst.googleWorkspace.enable inst.googleWorkspace.credentialsSecret)
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

      effectiveRuntimePlugins = lib.unique (
        inst.plugins.runtime
        ++ inst.runtimePlugins
        ++ lib.optional (inst.webSearch.enable && inst.webSearch.provider == "searxng") "searxng"
      );

      unknownPlugins = lib.filter (
        id: !(builtins.hasAttr id pkgs.openclawRuntimePlugins)
      ) effectiveRuntimePlugins;

      sandboxOrigin =
        if inst.sandbox.enable then "https://${inst.sandbox.subdomain}.${inst.domain}" else null;

      mcpAppsConfig = lib.optionalAttrs inst.sandbox.enable {
        mcp.apps = {
          # Required: without this switch OpenClaw never starts the sandbox listener, so the
          # public sandbox origin would answer 502 (verified live).
          enabled = true;
          sandboxPort = inst.sandbox.port;
          sandboxOrigin = sandboxOrigin;
        };
      };

      toolsConfig =
        lib.optionalAttrs (inst.webSearch.enable || inst.codeMode.enable || inst.toolSearch.enable)
          {
            tools =
              lib.optionalAttrs inst.webSearch.enable {
                web.search = {
                  enabled = true;
                  provider = inst.webSearch.provider;
                };
              }
              // lib.optionalAttrs inst.codeMode.enable {
                codeMode = "auto";
              }
              // lib.optionalAttrs inst.toolSearch.enable {
                toolSearch = {
                  enabled = true;
                };
              };
          };

      searxngPluginConfig =
        lib.optionalAttrs (inst.webSearch.enable && inst.webSearch.provider == "searxng")
          {
            searxng = {
              enabled = true;
              config = {
                webSearch = {
                  baseUrl = inst.webSearch.baseUrl;
                }
                // lib.optionalAttrs (inst.webSearch.categories != null) {
                  categories = inst.webSearch.categories;
                }
                // lib.optionalAttrs (inst.webSearch.language != null) {
                  language = inst.webSearch.language;
                };
              };
            };
          };

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
          entries =
            runtimePluginEntries
            // workboardConfig
            // activeMemoryConfig
            // searxngPluginConfig
            // extraPluginEntries;
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
            ]
            ++ lib.optional (ingressProxyAddress != null) ingressProxyAddress;
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
          agents = {
            defaults.model.primary = inst.defaultModel;
          }
          // lib.optionalAttrs (inst.agentName != null || inst.agentEmoji != null) {
            entries.main = {
              name = inst.agentName;
              workspace = "${stateDir}/workspace";
              identity = {
                name = inst.agentName;
              }
              // lib.optionalAttrs (inst.agentEmoji != null) {
                emoji = inst.agentEmoji;
              };
            };
          };
          talk = {
            speechLocale = "de-DE";
            realtime = {
              instructions = "Antworte immer auf Deutsch.";
            };
          };
        }
        // lib.optionalAttrs inst.browser.enable {
          browser = {
            enabled = true;
            headless = inst.browser.headless;
            noSandbox = inst.browser.noSandbox;
            executablePath = "${inst.browser.package}/bin/chromium";
            tabCleanup.enabled = inst.browser.tabCleanup;
          }
          //
            lib.optionalAttrs
              (
                inst.browser.ssrfPolicy.dangerouslyAllowPrivateNetwork
                || inst.browser.ssrfPolicy.allowedHostnames != [ ]
              )
              {
                ssrfPolicy =
                  lib.optionalAttrs inst.browser.ssrfPolicy.dangerouslyAllowPrivateNetwork {
                    dangerouslyAllowPrivateNetwork = true;
                  }
                  // lib.optionalAttrs (inst.browser.ssrfPolicy.allowedHostnames != [ ]) {
                    allowedHostnames = inst.browser.ssrfPolicy.allowedHostnames;
                  };
              };
        }
        // toolsConfig
        // mcpAppsConfig
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
          default = osConfig.my.topology.domain;
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

        agentName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Display name for the primary agent (shown in Web UI header/dropdown).";
        };

        agentEmoji = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Signature emoji for the primary agent.";
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
          default = osConfig.my.topology.trustedSubnets or [ ];
          description = "CIDR ranges from which node pairings are auto-approved.";
        };

        openMeshFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open the instance port on the WireGuard mesh interface so the ingress can reach it.";
        };

        browser = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable dedicated headless Chromium browser for this gateway instance.";
          };

          headless = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Run the managed browser headless.";
          };

          noSandbox = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Disable Chromium sandbox flags (useful if systemd unprivileged sandboxing requires it).";
          };

          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.chromium;
            description = "Chromium package used by this gateway instance.";
          };

          tabCleanup = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable automatic cleanup of idle browser tabs opened by sessions.";
          };

          ssrfPolicy = {
            dangerouslyAllowPrivateNetwork = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Allow the browser to navigate to private-network address ranges.";
            };

            allowedHostnames = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Hostnames or IP literals allowed by browser SSRF guardrails.";
            };
          };
        };

        webSearch = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable native web search for this gateway instance.";
          };

          provider = lib.mkOption {
            type = lib.types.str;
            default = "searxng";
            description = "Web search provider id (e.g. searxng).";
          };

          baseUrl = lib.mkOption {
            type = lib.types.str;
            default = "http://127.0.0.1:8888";
            description = "Base URL for the search engine (e.g. SearXNG instance).";
          };

          categories = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional comma-separated SearXNG search categories (e.g. general,science,news).";
          };

          language = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "de-DE";
            description = "Default language code for SearXNG results.";
          };
        };

        sandbox = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable isolated MCP App and Canvas widget sandbox.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = inst.port + 100;
            description = "Internal loopback port for the sandbox HTTP listener.";
          };

          subdomain = lib.mkOption {
            type = lib.types.str;
            default = "sandbox.${inst.subdomain}";
            description = "Subdomain below baseDomain for the sandbox origin (must differ from gateway origin).";
          };
        };

        publishing = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable dynamic self-publishing via Unix domain sockets under *.pub.<subdomain>.<domain>.";
          };

          subdomain = lib.mkOption {
            type = lib.types.str;
            default = "pub.${inst.subdomain}";
            description = "Subdomain below baseDomain for self-published sockets (e.g. pub.<user>.ai).";
          };
        };

        googleWorkspace = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Google Workspace CLI (gogcli) integration for Gmail, Calendar, Drive, and more.";
          };

          credentialsSecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "ai/openclaw/google_credentials";
            description = "SOPS secret containing the Google OAuth desktop app credentials.json (client_id & client_secret).";
          };
        };

        codeMode = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Code Mode (code-driven tool orchestration via embedded quickjs-wasi).";
          };
        };

        toolSearch = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Tool Search (dynamic tool schema loading to reduce prompt context tokens).";
          };
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
            default = "ai/deepseek_api_key";
            description = "SOPS secret for DEEPSEEK_API_KEY.";
          };

          openai = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "ai/openai_api_key";
            description = "SOPS secret for OPENAI_API_KEY.";
          };

          password = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "ai/openclaw/gateway_password";
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
            default = "ai/openclaw/a2a/${name}";
            description = "SOPS secret used for A2A peer authentication.";
          };

          peers = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  url = lib.mkOption {
                    type = lib.types.str;
                    description = "Target peer URL (e.g. https://katja.ai.ops.vyrx.de).";
                  };
                  tokenSecret = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "SOPS secret containing bearer token for this peer.";
                  };
                };
              }
            );
            default = { };
            description = "Declared A2A peer gateways.";
          };
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = defaultBasePackages;
          description = "Packages added to the PATH of commands executed by this gateway instance.";
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

    # A gateway is the SSH *server* end of the node loopback tunnels: it authorizes the node
    # keys for root. The node side renders the matching private key (see the node feature's
    # tunnelPrivateKeySecret), so exactly one side owns each half of the credential.
    trustedNodeKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIIoWHt6VqxvAOIXkZXZdNiNzoQ32a2PoEvjM3oaDEj openclaw-node-tunnel"
      ];
      description = "SSH public keys allowed to open node tunnels on this gateway.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceSubmodule);
      default = { };
      description = "Declared OpenClaw gateway instances.";
    };
  };

  config = lib.mkIf (cfg.enable && enabledInstances != { }) {
    # Authorize the node tunnel keys. List options merge, so this adds to the fleet deploy
    # keys set by the ssh feature without replacing them.
    users.users.root.openssh.authorizedKeys.keys = cfg.trustedNodeKeys;

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

    # Allow caddy to traverse into /var/lib/openclaw for socket reverse_proxy
    users.users.caddy.extraGroups = [ "openclaw" ];

    # Collect all secrets used across all instances and grant openclaw access
    sops.secrets =
      lib.genAttrs
        (lib.unique (lib.concatMap (inst: inst._secretNames) (lib.attrValues enabledInstances)))
        (_: {
          owner = "openclaw";
          group = "openclaw";
        });

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
        "d ${inst._stateDir} 0750 openclaw caddy - -"
        "d ${builtins.dirOf inst._logPath} 0750 openclaw openclaw - -"
      ]
      ++ lib.optionals inst.publishing.enable [
        "d ${inst._stateDir}/run 0750 openclaw caddy - -"
        "d ${inst._stateDir}/run/sockets 0770 openclaw caddy - -"
      ]
      ++ lib.optionals inst.googleWorkspace.enable [
        "d ${inst._stateDir}/.config 0700 openclaw openclaw - -"
        "d ${inst._stateDir}/.config/gogcli 0700 openclaw openclaw - -"
        "d ${inst._stateDir}/.local 0700 openclaw openclaw - -"
        "d ${inst._stateDir}/.local/share 0700 openclaw openclaw - -"
        "d ${inst._stateDir}/.local/share/gogcli 0700 openclaw openclaw - -"
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
            // lib.optionalAttrs inst.publishing.enable {
              OPENCLAW_SOCKET_DIR = "${inst._stateDir}/run/sockets";
              OPENCLAW_PUB_DOMAIN = "${inst.publishing.subdomain}.${inst.domain}";
            }
            // lib.optionalAttrs (inst.gitAuthor.name != null) {
              GIT_AUTHOR_NAME = inst.gitAuthor.name;
              GIT_COMMITTER_NAME = inst.gitAuthor.name;
            }
            // lib.optionalAttrs (inst.gitAuthor.email != null) {
              GIT_AUTHOR_EMAIL = inst.gitAuthor.email;
              GIT_COMMITTER_EMAIL = inst.gitAuthor.email;
            }
            // lib.optionalAttrs inst.googleWorkspace.enable (
              {
                GOG_HOME = "${inst._stateDir}/.local/share/gogcli";
                GOG_KEYRING_BACKEND = "file";
                GOG_KEYRING_PASSWORD = builtins.hashString "sha256" "openclaw-gog-keyring-${name}";
              }
              // lib.optionalAttrs (inst.googleWorkspace.credentialsSecret != null) {
                GOG_CREDENTIALS_FILE = osConfig.sops.secrets.${inst.googleWorkspace.credentialsSecret}.path;
              }
            );

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
            ]
            ++ inst.extraPackages
            ++ lib.optional inst.googleWorkspace.enable pkgs.gogcli
            ++ lib.optional inst.browser.enable inst.browser.package;
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    # Register each instance into the central service catalog for Caddy, Firewall, and Monitoring
    my.contracts.provides = lib.listToAttrs (
      lib.map (
        name:
        let
          inst = enabledInstances.${name};
        in
        {
          name = inst._endpointName;
          value = {
            endpoints = {
              web = {
                port = inst.port;
                protocol = "tcp";
                scope = "public";
                auth = if inst.auth then "authentik" else "none";
                subdomain = inst.subdomain;
                domain = inst.domain;
                # Dynamically minted self-publishing hosts are the only names that
                # cannot be enumerated, so the wildcard is declared here (SSOT).
                extraDomains = lib.optional inst.publishing.enable "*.${inst.publishing.subdomain}.${inst.domain}";
                unauthenticatedPaths = [
                  "/j/*"
                  "/__openclaw__/worker*"
                  "/.well-known/agent-card.json"
                  "/.well-known/agent.json"
                  "/a2a/*"
                ];
                machineClientsBypassAuth = true;
                directAccess = {
                  enable = inst.openMeshFirewall;
                  protocol = "tcp";
                  interface = "wireguard";
                };
                dashboard = {
                  show = true;
                  displayName =
                    if inst.agentName != null then "OpenClaw (${inst.agentName})" else "OpenClaw (${name})";
                  category = "AI & Agents";
                  icon = "bot";
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
            // lib.optionalAttrs inst.sandbox.enable {
              sandbox = {
                port = inst.sandbox.port;
                protocol = "tcp";
                scope = "public";
                auth = "none";
                publicExempt = "sandbox surface guarded by the gateway token - REVIEW whether it must be public";
                subdomain = inst.sandbox.subdomain;
                domain = inst.domain;
                directAccess = {
                  enable = inst.openMeshFirewall;
                  protocol = "tcp";
                  interface = "wireguard";
                };
                monitoring = {
                  http = {
                    enable = true;
                    group = "AI-Sandbox";
                    path = "/mcp-app-sandbox";
                  };
                };
              };
            };
            storage = {
              stateDirs = [ inst._stateDir ];
            };
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    # Declarative Caddy virtual hosts for dynamic self-publishing via Unix domain sockets.
    # When a process binds to $OPENCLAW_SOCKET_DIR/<app>.sock, Caddy automatically proxies
    # https://<app>.pub.<subdomain>.<domain> to unix//var/lib/openclaw/instances/<name>/run/sockets/<app>.sock.
    # Caddy requires an 'ask' permission endpoint to prevent DDoS/abuse of on_demand TLS certificate issuance.
    # We expose an internal permission check on 127.0.0.1:18099 that verifies the incoming domain is valid.
    services.caddy = {
      globalConfig = ''
        on_demand_tls {
          ask http://127.0.0.1:18099/ask
        }
      '';

      virtualHosts = {
        # Internal loopback endpoint for Caddy's on_demand_tls ask query
        "http://127.0.0.1:18099" = {
          extraConfig = ''
            respond /ask 200
          '';
        };
      }
      // lib.listToAttrs (
        lib.concatMap (
          name:
          let
            inst = enabledInstances.${name};
            pubDomain = "${inst.publishing.subdomain}.${inst.domain}";
            # In Caddy, {http.request.host.labels.N} is 0-indexed from right to left (TLD = 0).
            # For a wildcard host like *.<pubDomain>, the app name is the leftmost label,
            # which corresponds to the number of dots in pubDomain + 1.
            labelIndex = toString (builtins.length (lib.splitString "." pubDomain));
          in
          lib.optional inst.publishing.enable {
            name = "*.${pubDomain}";
            value = {
              extraConfig = ''
                tls {
                  on_demand
                }

                # Dynamic Unix socket routing based on the leftmost subdomain label (the app name)
                reverse_proxy unix/${inst._stateDir}/run/sockets/{http.request.host.labels.${labelIndex}}.sock
              '';
            };
          }
        ) (lib.attrNames enabledInstances)
      );
    };
  };
}
