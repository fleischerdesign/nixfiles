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
          auth = true;
          adminUsers = [ "philipp@fleischer.design" ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Philipp Fleischer";
            email = "philipp@fleischer.design";
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
          auth = true;
          adminUsers = [
            "fleischerkatja74@yahoo.com"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Katja Fleischer";
            email = "fleischerkatja74@yahoo.com";
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
          auth = true;
          adminUsers = [
            "lillytobei@gmail.com"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Lilly Tobei";
            email = "lillytobei@gmail.com";
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
          auth = true;
          adminUsers = [
            "kugelblitz82@gmx.de"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [
            "deepseek"
            "tokenjuice"
          ];
          gitAuthor = {
            name = "Kai Fleischer";
            email = "kugelblitz82@gmx.de";
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
          auth = true;
          adminUsers = [
            "rieke@vyrx.de"
            "philipp@fleischer.design"
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
            url = "https://katja.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          kai = {
            url = "https://kai.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.katja.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          kai = {
            url = "https://kai.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.lilly.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          katja = {
            url = "https://katja.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          kai = {
            url = "https://kai.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.kai.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          katja = {
            url = "https://katja.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          rieke = {
            url = "https://rieke.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/rieke";
          };
        };
      };

      instances.rieke.a2a = {
        peers = {
          philipp = {
            url = "https://philipp.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/philipp";
          };
          katja = {
            url = "https://katja.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/katja";
          };
          lilly = {
            url = "https://lilly.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/lilly";
          };
          kai = {
            url = "https://kai.ai.${config.my.features.services.caddy.baseDomain}";
            tokenSecret = "ai/openclaw/a2a/kai";
          };
        };
      };
    };

  # Direct alias / redirect for ai.<baseDomain> -> philipp.ai.<baseDomain>
  services.caddy.virtualHosts."ai.${config.my.features.services.caddy.baseDomain}".extraConfig = ''
    redir https://philipp.ai.${config.my.features.services.caddy.baseDomain}{uri} permanent
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
    domain = "search.${config.my.features.services.caddy.baseDomain}";
    auth = true;
    openTailscaleFirewall = true;
    enableJsonApi = true;
  };

  system.stateVersion = "24.11";
}
