{ inputs, config, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "cld-ops-01";

  my.features.services.caddy.baseDomain = "ops.vyrx.de";

  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.services.monitoring = {
    pipeline = {
      enable = true;
      role = "collector";
    };
  };

  my.features.services.attic.server.enable = true;

  my.features.services.crowdsec = {
    enable = true;
    role = "agent";
    excludeLogPatterns = [
      ".*cache.*"
      ".*ai.*"
    ];
  };

  my.features.services.openclaw.gateway =
    let
      commonDeepseekProvider = {
        baseUrl = "https://api.deepseek.com";
        api = "openai-completions";
        apiKey = "$DEEPSEEK_API_KEY";
        models = [
          {
            id = "deepseek-flash";
            name = "DeepSeek Flash (V4.1)";
            reasoning = true;
            input = [
              "text"
              "image"
            ];
            contextWindow = 1000000;
            maxTokens = 384000;
            cost = {
              input = 0.14;
              output = 0.28;
              cacheRead = 0.0028;
              cacheWrite = 0;
            };
            compat = {
              supportsUsageInStreaming = true;
              supportsReasoningEffort = true;
              maxTokensField = "max_tokens";
              codeMode = "preferred";
              requiresReasoningContentOnAssistantMessages = true;
            };
          }
        ];
      };
    in
    {
      enable = true;
      instances = {
        philipp = {
          enable = true;
          agentName = "Moebius";
          agentEmoji = "🌀";
          port = 18789;
          subdomain = "philipp.ai";
          domain = config.my.topology.domain;
          auth = true;
          adminUsers = [
            "philipp@vyrx.de"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Philipp Fleischer";
            email = "philipp@vyrx.de";
          };
          secrets = {
            github = "users/philipp/github_pat";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace.enable = true;
          settings.models.providers.deepseek = commonDeepseekProvider;
        };

        katja = {
          enable = true;
          agentName = "Frida";
          agentEmoji = "🌸";
          port = 18791;
          subdomain = "katja.ai";
          domain = config.my.topology.domain;
          auth = true;
          adminUsers = [
            "katja@vyrx.de"
            "fleischerkatja74@yahoo.com"
            "philipp@vyrx.de"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Katja Fleischer";
            email = "katja@vyrx.de";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace.enable = true;
          settings.models.providers.deepseek = commonDeepseekProvider;
        };

        lilly = {
          enable = true;
          agentName = "Cleo";
          agentEmoji = "✨";
          port = 18792;
          subdomain = "lilly.ai";
          domain = config.my.topology.domain;
          auth = true;
          adminUsers = [
            "lilly@vyrx.de"
            "lillytobei@gmail.com"
            "philipp@vyrx.de"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Lilly Tobei";
            email = "lilly@vyrx.de";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace.enable = true;
          settings.models.providers.deepseek = commonDeepseekProvider;
        };
        kai = {
          enable = true;
          agentName = "Keno";
          agentEmoji = "⚡";
          port = 18793;
          subdomain = "kai.ai";
          domain = config.my.topology.domain;
          auth = true;
          adminUsers = [
            "kai@vyrx.de"
            "kugelblitz82@gmx.de"
            "philipp@vyrx.de"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Kai Fleischer";
            email = "kai@vyrx.de";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace.enable = true;
          settings.models.providers.deepseek = commonDeepseekProvider;
        };

        rieke = {
          enable = true;
          agentName = "Rieke";
          agentEmoji = "🌸";
          port = 18794;
          subdomain = "rieke.ai";
          domain = config.my.topology.domain;
          auth = true;
          adminUsers = [
            "rieke@vyrx.de"
            "philipp@vyrx.de"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Rieke Fleischer";
            email = "rieke@vyrx.de";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace.enable = true;
          settings.models.providers.deepseek = commonDeepseekProvider;
        };
      };

      # Mutually peer all instances on cld-ops-01 via A2A with unique per-instance tokens
      instances.philipp.a2a = {
        peers = {
          katja = {
            url = "https://katja.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          kai = {
            url = "https://kai.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.katja.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          kai = {
            url = "https://kai.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.lilly.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          katja = {
            url = "https://katja.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          kai = {
            url = "https://kai.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.kai.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          katja = {
            url = "https://katja.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.rieke.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          katja = {
            url = "https://katja.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          kai = {
            url = "https://kai.ai.${config.my.topology.domain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
        };
      };
    };

  # Direct alias / redirect for ai.vyrx.de -> philipp.ai.vyrx.de
  services.caddy.virtualHosts."ai.${config.my.topology.domain}".extraConfig = ''
    redir https://philipp.ai.${config.my.topology.domain}{uri} permanent
  '';

  my.features.services.authentik.outpost.proxy = {
    enable = true;
  };

  my.features.services.obsidian-livesync-bridge = {
    enable = true;
    instances.philipp = {
      enable = true;
      couchdb.url = "https://livesync.edge.vyrx.de";
      couchdb.database = "obsidian-vault";
    };
  };

  my.features.services.searxng = {
    enable = true;
    port = 8888;
    domain = "search.${config.my.topology.domain}";
    auth = true;
    openTailscaleFirewall = true;
    enableJsonApi = true;
  };

  system.stateVersion = "24.11";
}
