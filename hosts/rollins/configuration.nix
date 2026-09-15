{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "rollins";

  my.features.services.caddy.baseDomain = "rls.ancoris.ovh";

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
          port = 18789;
          subdomain = "philipp.ai";
          auth = true;
          adminUsers = [ "philipp@fleischer.design" ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [ "deepseek" ];
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
          settings.models.providers.deepseek = commonDeepseekProvider;
        };

        katja = {
          enable = true;
          port = 18791;
          subdomain = "katja.ai";
          auth = true;
          adminUsers = [
            "fleischerkatja74@yahoo.com"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [ "deepseek" ];
          gitAuthor = {
            name = "Katja Fleischer";
            email = "fleischerkatja74@yahoo.com";
          };
          secrets = {
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
          };
          settings.models.providers.deepseek = commonDeepseekProvider;
        };

        lilly = {
          enable = true;
          port = 18792;
          subdomain = "lilly.ai";
          auth = true;
          adminUsers = [
            "lillytobei@gmail.com"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [ "deepseek" ];
          gitAuthor = {
            name = "Lilly Tobei";
            email = "lillytobei@gmail.com";
          };
          secrets = {
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
          };
          settings.models.providers.deepseek = commonDeepseekProvider;
        };

        kai = {
          enable = true;
          port = 18793;
          subdomain = "kai.ai";
          auth = true;
          adminUsers = [
            "kugelblitz82@gmx.de"
            "philipp@fleischer.design"
          ];
          defaultModel = "deepseek/deepseek-flash";
          memorySearch = "openai";
          runtimePlugins = [ "deepseek" ];
          gitAuthor = {
            name = "Kai Fleischer";
            email = "kugelblitz82@gmx.de";
          };
          secrets = {
            deepseek = "pi/deepseek";
            openai = "openai_api_key";
            password = "openclaw_gateway_password";
          };
          settings.models.providers.deepseek = commonDeepseekProvider;
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

  system.stateVersion = "24.11";
}
