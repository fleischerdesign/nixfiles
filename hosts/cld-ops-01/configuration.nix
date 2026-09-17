{ inputs, ... }:
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
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
            github = "github_pat_philipp";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace = {
            enable = true;
            credentialsSecret = "openclaw_google_credentials";
          };
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
          secrets = {
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace = {
            enable = true;
            credentialsSecret = "openclaw_google_credentials";
          };
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
          secrets = {
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace = {
            enable = true;
            credentialsSecret = "openclaw_google_credentials";
          };
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
          secrets = {
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
          };
          browser.enable = true;
          webSearch.enable = true;
          codeMode.enable = true;
          toolSearch.enable = true;
          googleWorkspace = {
            enable = true;
            credentialsSecret = "openclaw_google_credentials";
          };
          settings.models.providers.deepseek = commonDeepseekProvider;
        };
      };

      # Mutually peer all instances on rollins via A2A with unique per-instance tokens
      instances.philipp.a2a = {
        tokenSecret = "openclaw_a2a_token_philipp";
        peers = {
          katja = {
            url = "https://katja.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_katja";
          };
          lilly = {
            url = "https://lilly.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_lilly";
          };
          kai = {
            url = "https://kai.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_kai";
          };
        };
      };

      instances.katja.a2a = {
        tokenSecret = "openclaw_a2a_token_katja";
        peers = {
          philipp = {
            url = "https://philipp.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_philipp";
          };
          lilly = {
            url = "https://lilly.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_lilly";
          };
          kai = {
            url = "https://kai.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_kai";
          };
        };
      };

      instances.lilly.a2a = {
        tokenSecret = "openclaw_a2a_token_lilly";
        peers = {
          philipp = {
            url = "https://philipp.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_philipp";
          };
          katja = {
            url = "https://katja.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_katja";
          };
          kai = {
            url = "https://kai.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_kai";
          };
        };
      };

      instances.kai.a2a = {
        tokenSecret = "openclaw_a2a_token_kai";
        peers = {
          philipp = {
            url = "https://philipp.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_philipp";
          };
          katja = {
            url = "https://katja.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_katja";
          };
          lilly = {
            url = "https://lilly.ai.rls.ancoris.ovh";
            tokenSecret = "openclaw_a2a_token_lilly";
          };
        };
      };
    };

  # Direct alias / redirect for ai.rls.ancoris.ovh -> philipp.ai.rls.ancoris.ovh
  services.caddy.virtualHosts."ai.rls.ancoris.ovh".extraConfig = ''
    redir https://philipp.ai.rls.ancoris.ovh{uri} permanent
  '';

  my.features.services.camofox.enable = true;

  my.features.services.authentik.outpost.proxy = {
    enable = true;
    tokenSecretName = "authentik_outpost_proxy_token_rollins";
  };

  my.features.services.obsidian-livesync-bridge = {
    enable = true;
    instances.philipp = {
      enable = true;
      couchdb.url = "https://livesync.mky.ancoris.ovh";
      couchdb.database = "obsidian-vault";
    };
  };

  my.features.services.searxng = {
    enable = true;
    port = 8888;
    domain = "search.rls.ancoris.ovh";
    auth = true;
    openTailscaleFirewall = true;
    enableJsonApi = true;
  };

  system.stateVersion = "24.11";
}
