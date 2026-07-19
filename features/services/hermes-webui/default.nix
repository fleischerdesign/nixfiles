# features/services/hermes-webui/default.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.services.hermes-webui;
  hermesPkgs = import ../hermes-agent/python-packages.nix { inherit pkgs; };
in
{
  options.my.features.services.hermes-webui = {
    enable = lib.mkEnableOption "Hermes WebUI";
    port = lib.mkOption {
      type = lib.types.int;
      default = 8787;
      description = "Port the Hermes WebUI listens on";
    };
    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh/application/o/moebius";
      description = "OIDC Issuer URL (Authentik application endpoint).";
    };
    oidcClientId = lib.mkOption {
      type = lib.types.str;
      default = "moebius-webui";
      description = "OIDC Client ID.";
    };
    oidcAllowClaim = lib.mkOption {
      type = lib.types.str;
      default = "email";
      description = "OIDC claim used to validate access.";
    };
    oidcAllowValues = lib.mkOption {
      type = lib.types.str;
      default = "philipp@fleischer.design";
      description = "Comma-separated allowed values for the claim.";
    };
  };

  imports = [
    inputs.hermes-webui.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.features.services.hermes-agent.enable or false;
        message = "hermes-webui requires hermes-agent to be enabled on the same host.";
      }
    ];

    # Configure native WebUI service
    services.hermes-webui = {
      enable = true;
      inherit (cfg) port;
      host = "127.0.0.1";

      # Run as hermes user/group to seamlessly share folders
      user = "hermes";
      group = "hermes";

      # State and home path mapping (same as Docker container mounts)
      stateDir = "/var/lib/hermes/.hermes/webui";
      hermesHome = "/var/lib/hermes/.hermes";

      # Derive paths from the agent package
      agent.package = pkgs.hermes-agent;
      agent.dir = "${inputs.hermes-agent}";

      # Inject secret environment file containing API keys + OIDC client secret
      environmentFiles = lib.optionals (config.sops.secrets ? hermes_agent_env) [
        config.sops.secrets.hermes_agent_env.path
      ];

      # Inject OIDC config variables
      extraEnvironment = lib.filterAttrs (_: v: v != null) {
        HERMES_WEBUI_OIDC_ISSUER = cfg.oidcIssuer;
        HERMES_WEBUI_OIDC_CLIENT_ID = cfg.oidcClientId;
        HERMES_WEBUI_OIDC_ALLOW_CLAIM = cfg.oidcAllowClaim;
        HERMES_WEBUI_OIDC_ALLOW_VALUES = cfg.oidcAllowValues;
        HERMES_WEBUI_OIDC_REDIRECT_URI =
          let
            ep = config.my.endpoints.hermes-webui or { };
            domain =
              if ep ? proxy && ep.proxy.subdomain != null then
                "${ep.proxy.subdomain}.${ep.proxy.domain}"
              else
                null;
          in
          if domain != null then "https://${domain}/api/auth/oidc/callback" else null;

        # Override locations
        HERMES_API_URL = "http://127.0.0.1:8642";
        HERMES_WEBUI_DEFAULT_WORKSPACE = "/var/lib/hermes/workspace";
        HASS_URL = config.my.features.services.hermes-agent.hassUrl;
        PAPERLESS_URL = config.my.features.services.hermes-agent.paperlessUrl;
        CAMOFOX_URL = config.my.features.services.hermes-agent.camofoxUrl;
        MNEMOSYNE_EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2";
        PYTHONPATH = lib.mkBefore "${hermesPkgs.mnemosyne-hermes}/${pkgs.python312.sitePackages}:${hermesPkgs.mnemosyne-memory}/${pkgs.python312.sitePackages}";
      };
    };

    my.endpoints.hermes-webui = {
      host = config.networking.hostName;
      inherit (cfg) port;
    };
  };
}
