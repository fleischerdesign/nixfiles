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
  envSecret = variable: {
    source = "env";
    provider = "default";
    id = variable;
  };
  # Identifiers resolved through features/services/openclaw/plugins.nix. `tokenjuice` was active in the
  # previous OpenClaw feature and stays in use; the rest carry over the same way. `codex` is the agent
  # runtime the GPT-5.4 fallback routes through.
  enabledPlugins = [
    "deepseek"
    "diffs"
    "searxng"
    "lobster"
    "tokenjuice"
    "codex"
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
      inherit enabledPlugins;
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
        models.providers = {
          openai.apiKey = envSecret "OPENAI_API_KEY";
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
        agents = {
          ownership = "explicit";
          defaults = {
            model = {
              primary = "deepseek/deepseek-chat";
              fallbacks = [ "openai/gpt-5.4" ];
            };
            utilityModel = "deepseek/deepseek-chat";
            userTimezone = config.time.timeZone;
            workspace = "${instance.stateDir}/workspace";
            # `ownership = "explicit"` makes the four agents distinct, but ambient operations
            # (Ask OpenClaw, models.list, skills.status, unscoped session reads) still need one named
            # owner. Without it they fail with AgentSelectionRequiredError; `main` is the personal
            # assistant and the correct default for work that names no agent.
            systemAgent.agentId = "main";
            compaction = {
              mode = "safeguard";
              memoryFlush.enabled = true;
            };
            # There is no messenger channel, so a heartbeat has no owner address to deliver to. Runs
            # still execute and surface in the Control UI transcript; they must not silently claim a
            # delivered alert. Recurring checks belong in automation jobs with explicit targets.
            heartbeat = {
              every = "30m";
              target = "none";
            };
          };
          entries = {
            main = {
              name = "Personal assistant";
              subagents.allowAgents = [
                "coding"
                "research"
                "operations"
              ];
              # A personal agent may recall relevant context from its own other private
              # conversations. Only main gets this: the specialists are task personas, not people
              # with a memory of their own, and narrowing it to main keeps their transcripts out of
              # recall. Enabling this implies session transcript indexing for main.
              memory.search.rememberAcrossConversations = true;
            };
            coding = {
              name = "Coding specialist";
              model = "openai/gpt-5.4";
              workspace = "${instance.stateDir}/workspaces/coding";
            };
            research = {
              name = "Research specialist";
              workspace = "${instance.stateDir}/workspaces/research";
              # Research reads the open web. It may fetch and read, but it does not need to write
              # files or run shell commands, so its authority is narrowed to the read path.
              sandbox = {
                mode = "all";
                scope = "agent";
                workspaceAccess = "ro";
              };
              tools = {
                allow = [
                  "read"
                  "web_search"
                  "web_fetch"
                ];
                deny = [
                  "write"
                  "edit"
                  "apply_patch"
                  "exec"
                  "process"
                  "browser"
                ];
              };
            };
            operations = {
              name = "Fleet operations specialist";
              workspace = "${instance.stateDir}/workspaces/operations";
            };
          };
        };
        tools = {
          profile = "full";
          # Session visibility and agent-to-agent messaging are set explicitly so the default
          # Gateway-wide reach is a decision, not an oversight. `allow` lists the agent ids that may
          # be targeted; main owns the specialists, so only those names appear.
          sessions.visibility = "agent";
          agentToAgent = {
            enabled = true;
            allow = [
              "coding"
              "research"
              "operations"
            ];
          };
          exec = {
            host = "gateway";
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
          allow = builtinsPluginIds ++ enabledPlugins;
          entries =
            lib.genAttrs builtinsPluginIds (_: {
              enabled = true;
            })
            // lib.genAttrs enabledPlugins (_: {
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
              memory-core.config.dreaming.enabled = true;
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
