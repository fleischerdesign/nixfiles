{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.mealie;
  smtp = config.my.features.system.smtp;
  topologyDomain = config.my.topology.domain;
  authHost = "auth.${topologyDomain}";
in
{
  options.my.features.services.mealie = {
    enable = lib.mkEnableOption "Mealie Recipe Manager";
    smtpFromEmail = lib.mkOption {
      type = lib.types.str;
      default = smtp.fromAddress;
      description = "From address for SMTP outgoing mails.";
    };
    ssoConfigurationUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${authHost}/application/o/mealie/.well-known/openid-configuration";
      description = "OIDC discovery configuration endpoint URL.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.system.smtp.enable = true;
    # 1. Load individual secrets from sops file
    sops.secrets."services/apps/mealie_oidc_secret" = { };
    sops.secrets."services/apps/mealie_openai_key" = { };

    # 2. Create a template file that combines them into ENV format
    sops.templates."mealie.env" = {
      restartUnits = [ "mealie.service" ];
      content = ''
        SMTP_USER=${config.sops.placeholder.${smtp.usernameSecret}}
        SMTP_PASSWORD=${config.sops.placeholder.${smtp.passwordSecret}}
        OIDC_CLIENT_SECRET=${config.sops.placeholder."services/apps/mealie_oidc_secret"}
        OPENAI_API_KEY=${config.sops.placeholder."services/apps/mealie_openai_key"}
      '';
    };

    services.mealie = {
      enable = true;
      port = 9025;
      listenAddress = "0.0.0.0";

      # 3. Point Mealie to the generated template file
      credentialsFile = config.sops.templates."mealie.env".path;

      settings = {
        ALLOW_SIGNUP = "false";
        TZ = "Europe/Berlin";
        BASE_URL =
          let
            pub = config.my.contracts.provides.mealie.publications.web;
          in
          lib.mkIf (pub.publicUrl != null) pub.publicUrl;

        # SMTP Configuration
        SMTP_HOST = smtp.host;
        SMTP_PORT = toString smtp.port;
        SMTP_FROM_NAME = "Mealie";
        SMTP_AUTH_STRATEGY = if smtp.tls == "starttls" then "TLS" else "SSL";
        SMTP_FROM_EMAIL = cfg.smtpFromEmail;

        # OIDC Configuration
        OIDC_AUTH_ENABLED = "True";
        OIDC_SIGNUP_ENABLED = "True";
        OIDC_CONFIGURATION_URL = cfg.ssoConfigurationUrl;
        OIDC_CLIENT_ID = "uwxlwWIofaSVKwAJTyzhzT75kUMDfoCpmlSs4M1E";
        OIDC_ADMIN_GROUP = "infra-admins";
        OIDC_AUTO_REDIRECT = "True";
        OIDC_PROVIDER_NAME = "Authentik";
        OIDC_USER_CLAIM = "email";
        OIDC_NAME_CLAIM = "name";
        OIDC_REMEMBER_ME = "True";
        # Authentik liefert kein email_verified-Claim -> Prüfung deaktivieren
        OIDC_REQUIRES_EMAIL_VERIFICATION = "False";

        # OpenAI Configuration
        OPENAI_BASE_URL = "https://openrouter.ai/api/v1";
        OPENAI_MODEL = "gpt-5-mini";

        # Proxy Configuration
        FORWARDED_ALLOW_IPS = "*";
      };
    };

    # Workaround for nltk 3.9.2 requiring a writable download directory
    # when NLTK_DATA points to a read-only Nix store path.
    # TODO: remove when nixpkgs fixes this upstream.
    systemd.services.mealie.environment.HOME = "/var/lib/mealie";
    systemd.services.mealie.restartTriggers = [ config.sops.templates."mealie.env".file ];

    # Register with Caddy & Firewall via Service Contract
    my.contracts.provides.mealie = {
      publications."web" = {
        scope = "public";
        endpoint = "web";
        auth = "oidc";
        accessGroups = [ "family" ];
        subdomain = "mealie";
        # Ingress reaches this over the WireGuard mesh (invariant I10).
      };
      identity.oidc.web = {
        publication = "web";
        enable = true;
        clientId = "uwxlwWIofaSVKwAJTyzhzT75kUMDfoCpmlSs4M1E";
        clientSecretEnv = "AUTHENTIK_OIDC_MEALIE_SECRET";
        secretPath = "services/apps/mealie_oidc_secret";
        redirectPaths = [
          "/login"
        ];
        subMode = "hashed_user_id";
        includeClaimsInIdToken = true;
      };
      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Rezepte und Essensplanung.";
          en = "Recipes and meal planning.";
        };
        show = true;
        displayName = "Mealie";
        category = "Home";
        icon = "mealie";
      };
      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";
      telemetry.probes."web-http".path = "/api/app/about";
      endpoints.web = {
        port = 9025;
        protocol = "tcp";
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "wireguard";
        };

      };
      storage = {
        stateDirs = [ "/var/lib/mealie" ];
        dataDirs = [ ];
        cacheDirs = [ ];
      };
    };
  };
}
