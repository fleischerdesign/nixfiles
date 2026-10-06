{
  config,
  lib,
  pkgs,
  fleetConfigs,
  ...
}:
let
  name = "philipp";
  instance = config.my.features.services.openclaw.users.${name};
  gatewayConfig = (fleetConfigs.systems config).${instance.gatewayHost}.config;
  metadata = import ./metadata.nix;
  # Purpose-based routing; subscription chat, Go inference and API embeddings are separate paths.
  models = {
    main = "opencode-go/muse-spark-1.3-contributor";
    worker = "opencode-go/deepseek-v4.1-flash";
    free = "opencode-go/longcat-2.5-preview-free";
    multimodal = "opencode-go/mimo-v2.6-flash";
    # The ChatGPT OAuth chat route stays declared and is selectable by hand, but no purpose slot
    # routes to it any more; OpenAI remains the embedding and voice provider through its explicit
    # Platform API keys. Keeping the id here stops the OpenAI declaration from silently tracking the
    # main binding, which now lives on the Go route.
    chatgpt = "openai/gpt-6.1-sol";
  };
  # Minimal published Go metadata for reproducible isolated runs, which have no discovery cache.
  # Source: models.opencode.ai/api.json. Keep transport-compatible text/image capabilities here;
  # advertised audio/video inputs need separate qualification in OpenClaw's media adapters.
  goModel =
    ref: metadata:
    {
      id = lib.removePrefix "opencode-go/" ref;
      name = lib.removePrefix "opencode-go/" ref;
      reasoning = true;
      input = [
        "text"
        "image"
      ];
    }
    // metadata;
  envSecret = variable: {
    source = "env";
    provider = "default";
    id = variable;
  };
  # Additional runtime plugins are installed by nix-openclaw, not repackaged as bundled plugins.
  runtimePlugins = [
    "deepseek"
    "searxng"
    "lobster"
    "tokenjuice"
  ];
  # Plugins that ship inside OpenClaw and only need enablement. `device-pair` provides node onboarding
  # join codes; without it the native nodes cannot be paired.
  builtinsPluginIds = [
    "openai"
    "openrouter"
    "opencode-go"
    "browser"
    "web-readability"
    "memory-core"
    "active-memory"
    "canvas"
    "document-extract"
    "file-transfer"
    "llm-task"
    "session-share"
    "talk-voice"
    "workboard"
    "device-pair"
    "linux-node"
  ];
in
{
  my.features.services.openclaw = {
    users.${name} = {
      port = 18789;
      apps = {
        enable = true;
        # OpenClaw derives MCP Apps from the gateway port (gateway+1) and Browser Control from
        # gateway+2. Leave the port unset so the two never collide; the derived default is 18790.
      };
      publishing = {
        enable = true;
        # Leave the port unset: the derived default (gateway+2048) stays clear of the Browser Control
        # and managed Chrome CDP ports that OpenClaw derives from the gateway port.
      };
      fleet = {
        enable = true;
        hosts = lib.attrNames (fleetConfigs.systems config);
        # One credential pair per gateway. The private half lives in SOPS under this person's own
        # path; the public half is authorized only on the declared targets. Adding a person means
        # adding their pair, not sharing this one.
        privateKeySecret = "users/philipp/openclaw/fleet_private_key";
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP8ER6xTwR8a735K+pwIFTOLLl1IElKy7FytXFJYFey1 openclaw-philipp-gateway";
      };
      packages = with pkgs; [
        bashInteractive
        git
        gh
        openssh
        nix
        nixos-rebuild
        jq
        ripgrep
        fd
        curl
        python3
        nodejs
        chromium
        openssl
        socat
      ];
      skillDirectories = [ ./openclaw-skills ];
      inherit runtimePlugins;
      secrets = {
        OPENAI_API_KEY = "ai/openai_api_key";
        DEEPSEEK_API_KEY = "ai/deepseek_api_key";
        OPENROUTER_API_KEY = "ai/openrouter_api_key";
        # OpenCode's Zen and Go catalogs share one credential; Go entitlement is decided by the
        # account/workspace the key belongs to, not by a Go-specific key.
        OPENCODE_API_KEY = "ai/opencode_api_key";
        GH_TOKEN = "users/philipp/github_pat";
        OPENCLAW_GATEWAY_PASSWORD = "ai/openclaw/gateway_password";
      };
      google = {
        enable = true;
        credentialsSecret = "ai/openclaw/google_credentials";
      };
      obsidianBridge = name;
      environment = {
        GIT_AUTHOR_NAME = metadata.fullName;
        GIT_AUTHOR_EMAIL = metadata.email;
        GIT_COMMITTER_NAME = metadata.fullName;
        GIT_COMMITTER_EMAIL = metadata.email;
      };
      settings = {
        wizard.accessMode = "full";
        # Persistent operator consent, not device admission: each node must independently enable
        # and advertise capture and have its expanded command surface approved.
        gateway.nodes.commands.allow = [
          "camera.snap"
          "camera.clip"
        ];
        models.providers = {
          # Chat inference must not fall through to the separately configured embedding/voice key.
          openai = {
            auth = "oauth";
            # This release's catalogue predates Sol. Declare its native subscription transport,
            # without selecting the unrelated Codex app-server agent harness.
            models = [
              {
                id = lib.removePrefix "openai/" models.chatgpt;
                name = "GPT-6.1 Sol";
                api = "openai-chatgpt-responses";
                # OAuth account catalogue (/codex/models, client_version=0.160.0):
                # max_context_window is capacity; context_window is the default runtime budget.
                contextWindow = 872000;
                contextTokens = 272000;
                reasoning = true;
                input = [
                  "text"
                  "image"
                ];
              }
            ];
          };
          opencode-go = {
            apiKey = envSecret "OPENCODE_API_KEY";
            baseUrl = "https://opencode.ai/zen/go/v1";
            api = "openai-completions";
            models = [
              (goModel models.main {
                contextWindow = 1048576;
                maxTokens = 131072;
                cost = {
                  input = 0.1;
                  output = 0.2;
                  cacheRead = 0.002;
                  cacheWrite = 0;
                };
              })
              (goModel models.free {
                contextWindow = 1000000;
                maxTokens = 131072;
                cost = {
                  input = 0;
                  output = 0;
                  cacheRead = 0;
                  cacheWrite = 0;
                };
              })
              (goModel models.worker {
                contextWindow = 1000000;
                maxTokens = 384000;
                cost = {
                  input = 0.15;
                  output = 0.6;
                  cacheRead = 0.003;
                  cacheWrite = 0;
                };
              })
              (goModel models.multimodal {
                contextWindow = 1048576;
                maxTokens = 131072;
                cost = {
                  input = 0.14;
                  output = 0.28;
                  cacheRead = 0.0028;
                  cacheWrite = 0;
                };
              })
            ];
          };
          deepseek.apiKey = envSecret "DEEPSEEK_API_KEY";
          openrouter.apiKey = envSecret "OPENROUTER_API_KEY";
        };
        # Talk: speech and realtime voice both run through OpenAI. Provider, model and speaker
        # voice stay on the provider default until one is chosen deliberately; the schema's
        # defaults are the documented starting point, not a missing decision.
        talk = {
          provider = "openai";
          providers.openai.apiKey = envSecret "OPENAI_API_KEY";
          realtime = {
            provider = "openai";
            providers.openai.apiKey = envSecret "OPENAI_API_KEY";
          };
        };
        # Durable transcripts are the source the session-recall paths index; without them
        # `rememberAcrossConversations` has nothing to read. Durable, explicit, and not inferred.
        transcripts.enabled = true;
        # File logs hold detail (level info) while the journal stays quiet; a stable path under the
        # state directory keeps diagnostics with the runtime they describe instead of a volatile
        # /tmp default. `redactPatterns` keep credential-shaped material out of both.
        logging = {
          level = "info";
          consoleLevel = "warn";
          file = "${instance.stateDir}/logs/gateway.log";
          maxFileBytes = 16777216;
          redactPatterns = [
            "sk-[A-Za-z0-9]{16,}"
            "oc_sk_[A-Za-z0-9]{16,}"
            "ghp_[A-Za-z0-9]{16,}"
            "-----BEGIN [A-Z ]*PRIVATE KEY-----"
            "[Bb]earer [A-Za-z0-9._-]{16,}"
          ];
        };
        session = {
          # Reset is a named action, never an accident; every spelling is listed because aliases are
          # not added automatically. Everything else - scope, sharing, store - is chosen by the
          # runtime's documented defaults, which fit one operator on one gateway.
          resetTriggers = [
            "/new"
            "/reset"
          ];
        };
        # Retain attachment context for seven days; durable sessions remain the source of truth.
        attachments.ttlHours = 168;
        # Managed worktrees belong to the runtime, not the workspace of one agent.
        worktreeRoot = "${instance.stateDir}/worktrees";
        worktreeAcceleration = true;
        agents = {
          ownership = "explicit";
          defaults = {
            model = {
              primary = models.main;
              fallbacks = [
                models.worker
                models.multimodal
              ];
            };
            utilityModel = models.free;
            models = {
              # Subscription transport and agent execution are separate choices. Native execution
              # retains paired-device placement instead of inheriting the implicit Codex harness.
              "openai/*".agentRuntime.id = "openclaw";
              "opencode-go/*" = { };
            };
            subagents.model = models.worker;
            userTimezone = config.time.timeZone;
            workspace = "${instance.stateDir}/workspace";
            # Ambient operations under `ownership = "explicit"`
            # (Ask OpenClaw, models.list, skills.status, unscoped session reads) still need one named
            # owner. Without it they fail with AgentSelectionRequiredError; `main` is the personal
            # assistant and the correct default for work that names no agent.
            systemAgent.agentId = "main";
            compaction = {
              mode = "safeguard";
              # Native Codex compaction remains runtime-owned; this selects embedded summaries.
              model = models.free;
              memoryFlush = {
                enabled = true;
                model = models.free;
              };
            };
            # There is no messenger channel, so a heartbeat has no owner address to deliver to. Runs
            # still execute and surface in the Control UI transcript; they must not silently claim a
            # delivered alert. Recurring checks belong in automation jobs with explicit targets.
            heartbeat = {
              every = "30m";
              target = "none";
              model = models.worker;
            };
          };
          entries = {
            main = {
              # Keep the stable id: existing conversations, memory and plugin scopes belong to main.
              name = "Moebius";
              identity.name = "Moebius";
              subagents.allowAgents = [ "main" ];
              # Cross-conversation recall belongs to this personal agent. Enabling it implies
              # session transcript indexing without a Gateway-wide sources override.
              memory.search.rememberAcrossConversations = true;
            };
          };
        };
        tools = {
          profile = "full";
          # One configured agent: temporary child runs use its existing subagent return channel,
          # not a separate cross-agent messaging topology.
          sessions.visibility = "agent";
          agentToAgent = {
            enabled = false;
            allow = [ ];
          };
          exec = {
            # Auto keeps unsandboxed calls on the gateway but permits an explicit paired-node
            # target. A fixed gateway host rejects node overrides and hides node-hosted skills.
            host = "auto";
            mode = "full";
            # Keep apply_patch inside the agent workspace even though exec runs unsandboxed; the
            # filesystem tools already reach the host deliberately, so a patch should not also escape
            # its workspace silently.
            applyPatch.workspaceOnly = true;
          };
          fs.workspaceOnly = false;
          web.search = {
            enabled = true;
            provider = "searxng";
          };
        };
        memory.search = {
          enabled = true;
          provider = "openai";
          model = "text-embedding-3-small";
          remote.apiKey = envSecret "OPENAI_API_KEY";
          # Both the vault and, once rememberAcrossConversations is on, conversation transcripts are
          # sent to OpenAI to be embedded. That is a deliberate data-flow decision, not an accident of
          # the default provider; docs/openclaw.md states it. Switching to a local provider (ollama or
          # llama.cpp) removes the egress and requires a full reindex.
          extraPaths = [
            gatewayConfig.my.features.services.obsidian-livesync-bridge.instances.${name}._targetVaultPath
          ];
        };
        browser = {
          enabled = true;
          headless = true;
          executablePath = "${pkgs.chromium}/bin/chromium";
          # The private-network allowance exists so the browser can reach SearXNG and other
          # contract-declared internal services. It is not a general opening: the mesh and the
          # firewall remain the network boundary, and the browser SSRF guard is defence in depth
          # rather than a substitute for either.
          ssrfPolicy.dangerouslyAllowPrivateNetwork = true;
        };
        # The standalone loopback Browser Control API authenticates with a shared secret only; a
        # trusted-proxy identity does not reach it. OpenClaw would otherwise generate a password and
        # try to persist it into the config, which is immutable here. Naming the secret keeps the
        # control API usable by the gateway's own tooling without a runtime write.
        gateway.auth.password = envSecret "OPENCLAW_GATEWAY_PASSWORD";
        plugins = {
          # Built-in plugin ids plus the external identifiers the catalogue resolves. A profile names
          # identifiers once; `allow` and `entries` are derived, so a plugin cannot be packaged and
          # loaded while silently left out of the allowlist.
          allow = builtinsPluginIds ++ runtimePlugins;
          entries =
            lib.genAttrs builtinsPluginIds (_: {
              enabled = true;
            })
            // lib.genAttrs runtimePlugins (_: {
              enabled = true;
            })
            // {
              searxng = {
                enabled = true;
                config.webSearch.baseUrl = gatewayConfig.my.contracts.provides.searxng.endpoints.web.localUrl;
              };
              # Deep recall for eligible private conversations. `escalate` runs the blocking recall
              # sub-agent only when the message asks about the past and the deterministic lane found
              # no strong trusted hit, so ordinary replies keep their latency. Scoped to direct
              # conversations of `main`.
              active-memory = {
                enabled = true;
                config = {
                  enabled = true;
                  model = models.free;
                  mode = "escalate";
                  agents = [ "main" ];
                  allowedChatTypes = [ "direct" ];
                  queryMode = "recent";
                  promptStyle = "balanced";
                  timeoutMs = 15000;
                  maxSummaryChars = 220;
                  persistTranscripts = false;
                  logging = true;
                };
              };
              # Dreaming is on by default; naming it here makes the consolidation pass a reviewed
              # decision. Whether its scheduled sweep actually fires depends on the default agent's
              # heartbeat, which runs with target = "none" in this deployment.
              memory-core = {
                enabled = true;
                subagent = {
                  allowModelOverride = true;
                  allowedModels = [ models.free ];
                };
                config.dreaming = {
                  enabled = true;
                  model = models.free;
                };
              };
              llm-task = {
                enabled = true;
                config = {
                  defaultProvider = "opencode-go";
                  defaultModel = lib.removePrefix "opencode-go/" models.free;
                };
              };
            };
          slots.memory = "memory-core";
        };
        discovery.mdns.mode = "off";
        cron.enabled = true;
        skills = {
          allowBundled = [
            "gog"
            "github"
            "gh-issues"
            "coding-agent"
            "obsidian"
            "session-logs"
            "skill-creator"
            "summarize"
            "weather"
          ];
          install = {
            preferBrew = false;
            allowUploadedArchives = false;
          };
          workshop.autonomous.mode = "off";
        };
        channels = { };
      };
    };
  };

}
