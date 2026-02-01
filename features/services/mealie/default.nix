{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.mealie;
in
{
  options.my.features.services.mealie = {
    enable = lib.mkEnableOption "Mealie Recipe Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "mealie"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Load individual secrets from sops file
    sops.secrets.mealie_smtp_password = { sopsFile = ../../../secrets/secrets.yaml; };
    sops.secrets.mealie_oidc_secret = { sopsFile = ../../../secrets/secrets.yaml; };
    sops.secrets.mealie_openai_key = { sopsFile = ../../../secrets/secrets.yaml; };

    # 2. Create a template file that combines them into ENV format
    sops.templates."mealie.env" = {
      content = ''
        SMTP_PASSWORD=${config.sops.secrets.mealie_smtp_password.placeholder}
        OIDC_CLIENT_SECRET=${config.sops.secrets.mealie_oidc_secret.placeholder}
        OPENAI_API_KEY=${config.sops.secrets.mealie_openai_key.placeholder}
      '';
    };

    services.mealie = {
      enable = true;
      port = 9025;
      listenAddress = "127.0.0.1";
      
      # 3. Point Mealie to the generated template file
      credentialsFile = config.sops.templates."mealie.env".path;

      settings = {
        ALLOW_SIGNUP = "false";
        TZ = "Europe/Berlin";
        BASE_URL = "https://${cfg.expose.subdomain}.${config.my.features.services.caddy.baseDomain}";
        
        # SMTP Configuration
        SMTP_HOST = "mail.smtp2go.com";
        SMTP_PORT = "2525";
        SMTP_FROM_NAME = "Mealie";
        SMTP_AUTH_STRATEGY = "TLS";
        SMTP_FROM_EMAIL = "noreply@ancoris.ovh";
        SMTP_USER = "ancoris";

        # OIDC Configuration
        OIDC_AUTH_ENABLED = "True";
        OIDC_SIGNUP_ENABLED = "True";
        OIDC_CONFIGURATION_URL = "https://auth.ancoris.ovh/application/o/mealie/.well-known/openid-configuration";
        OIDC_CLIENT_ID = "uwxlwWIofaSVKwAJTyzhzT75kUMDfoCpmlSs4M1E";
        OIDC_ADMIN_GROUP = "Mealie Admins";
        OIDC_AUTO_REDIRECT = "True";
        OIDC_PROVIDER_NAME = "Authentik";
        OIDC_USER_CLAIM = "email";
        OIDC_NAME_CLAIM = "name";

        # OpenAI Configuration
        OPENAI_BASE_URL = "https://openrouter.ai/api/v1";
        OPENAI_MODEL = "gpt-5-mini";
      };
    };

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "mealie" = {
        port = 9025;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
