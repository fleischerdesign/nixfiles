# features/services/open-webui/default.nix
# Open-WebUI multi-user AI platform (ChatGPT-compatible web interface, memory, tools).
#
# Integration:
# - Service: Nixpkgs upstream `services.open-webui`
# - Endpoint Contract: `my.contracts.provides.open-webui` exposing `ai.vyrx.de`
# - Identity & Access: Authentik SSO via OIDC (`accessGroups = [ "family" ]`)
# - Secrets: Rendered dynamically via SOPS template into an EnvironmentFile
# - Persistence & Backups: Registered with storage and backup contracts
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.open-webui;
  topologyDomain = config.my.topology.domain;
  authHost = "auth.${topologyDomain}";
  canonicalHost = "${cfg.subdomain}.${topologyDomain}";
in
{
  options.my.features.services.open-webui = {
    enable = lib.mkEnableOption "Open-WebUI multi-user AI platform";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8088;
      description = "Internal network port Open-WebUI listens on.";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ai";
      description = "Subdomain under apex domain (e.g. 'ai' -> ai.vyrx.de).";
    };

    accessGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "family" ];
      description = "Authentik groups whose members may access Open-WebUI.";
    };

    openMeshFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow direct access to the Open-WebUI port over the WireGuard mesh interface.";
    };

    sso = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Authentik OIDC single sign-on.";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "open-webui";
        description = "OIDC Client ID in Authentik.";
      };

      secretPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "ai/openrouter_api_key";
        description = "SOPS secret path holding the client secret.";
      };
    };

    models = {
      deepseekApiKeySecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "ai/deepseek_api_key";
        description = "SOPS secret path for DEEPSEEK_API_KEY.";
      };

      openaiApiKeySecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "ai/openai_api_key";
        description = "SOPS secret path for OPENAI_API_KEY.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS Secret Declarations
    sops.secrets = lib.mkMerge [
      (lib.optionalAttrs (cfg.models.deepseekApiKeySecret != null) {
        ${cfg.models.deepseekApiKeySecret} = { };
      })
      (lib.optionalAttrs (cfg.models.openaiApiKeySecret != null) {
        ${cfg.models.openaiApiKeySecret} = { };
      })
      (lib.optionalAttrs (cfg.sso.enable && cfg.sso.secretPath != null) {
        ${cfg.sso.secretPath} = { };
      })
    ];

    # 2. SOPS Environment Template (Never leaks plaintext secrets to Nix store)
    sops.templates."open-webui.env" = {
      content = ''
        ${lib.optionalString (cfg.models.deepseekApiKeySecret != null) ''
          DEEPSEEK_API_KEY=${config.sops.placeholder.${cfg.models.deepseekApiKeySecret}}
        ''}
        ${lib.optionalString (cfg.models.openaiApiKeySecret != null) ''
          OPENAI_API_KEY=${config.sops.placeholder.${cfg.models.openaiApiKeySecret}}
        ''}
        ${lib.optionalString (cfg.sso.enable && cfg.sso.secretPath != null) ''
          OAUTH_CLIENT_SECRET=${config.sops.placeholder.${cfg.sso.secretPath}}
        ''}
        OPENAI_API_BASE_URLS=https://api.deepseek.com/v1;https://api.openai.com/v1
        OPENAI_API_KEYS=''${DEEPSEEK_API_KEY};''${OPENAI_API_KEY}
      '';
    };

    # 3. Native Nixpkgs Open-WebUI service configuration
    services.open-webui = {
      enable = true;
      host = "0.0.0.0";
      port = cfg.port;
      environmentFile = config.sops.templates."open-webui.env".path;
      environment = {
        ENV = "prod";
        WEBUI_URL = "https://${canonicalHost}";
        # Telemetry & tracking opt-out
        SCARF_NO_ANALYTICS = "True";
        DO_NOT_TRACK = "True";
        ANONYMIZED_TELEMETRY = "False";

        # OIDC / Authentik configuration
        ENABLE_OAUTH_SIGNUP = if cfg.sso.enable then "True" else "False";
        OAUTH_PROVIDER_NAME = "Authentik";
        OAUTH_CLIENT_ID = cfg.sso.clientId;
        OPENID_PROVIDER_URL = "https://${authHost}/application/o/${cfg.sso.clientId}/.well-known/openid-configuration";
        OPENID_REDIRECT_URI = "https://${canonicalHost}/oauth/oidc/callback";
        OAUTH_SCOPES = "openid email profile";

        # Features & Tools
        ENABLE_COMMUNITY_SHARING = "False";
        DEFAULT_MODELS = "deepseek-chat";
      };
    };

    # 4. Service Contract Declarations (Single Source of Truth)
    my.contracts.provides.open-webui = {
      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
        scope = "public";
        auth = if cfg.sso.enable then "oidc" else "none";
        accessGroups = cfg.accessGroups;
        subdomain = cfg.subdomain;
        directAccess = {
          enable = cfg.openMeshFirewall;
          protocol = "tcp";
          interface = "wireguard";
        };
        oidc = lib.optionalAttrs cfg.sso.enable {
          enable = true;
          clientId = cfg.sso.clientId;
          secretPath = cfg.sso.secretPath;
          redirectPaths = [ "/oauth/oidc/callback" ];
          subMode = "hashed_user_id";
          includeClaimsInIdToken = true;
        };
        dashboard = {
          description = {
            de = "Zentrale KI-Plattform für Chat, Reasoning & Tools.";
            en = "Central AI platform for chat, reasoning & tools.";
          };
          show = true;
          displayName = "AI Assistant (Open-WebUI)";
          category = "AI & Agents";
          icon = "bot";
        };
      };

      storage = {
        stateDirs = [ config.services.open-webui.stateDir ];
      };
    };
  };
}
