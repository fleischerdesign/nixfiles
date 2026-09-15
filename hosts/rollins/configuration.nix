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

  my.features.services.openclaw.gateway = {
    enable = true;
    subdomain = "ai";
    auth = true;
    adminUsers = [ "philipp@fleischer.design" ];
    defaultModel = "deepseek/deepseek-flash";
    memorySearch = "openai";
    runtimePlugins = [ "deepseek" ];
    secrets = {
      deepseek = "pi/deepseek";
      openai = "openai_api_key";
      password = "openclaw_gateway_password";
      github = "github_pat_philipp";
    };

    # The DeepSeek runtime plugin still ships the retired `deepseek-v4-*` catalogue and
    # only applies its thinking profile to ids with that prefix, while the DeepSeek API
    # already serves `deepseek-flash`. Declaring the current model explicitly keeps the
    # plugin's provider family (request shaping, reasoning_content replay) and adds the
    # correct catalogue entry; compat/cost mirror the plugin manifest.
    settings.models.providers.deepseek = {
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
  };

  my.features.services.camofox.enable = true;

  my.features.services.authentik.outpost.proxy = {
    enable = true;
    tokenSecretName = "authentik_outpost_proxy_token_rollins";
  };

  system.stateVersion = "24.11";
}
