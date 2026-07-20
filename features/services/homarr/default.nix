{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.homarr;
in
{
  options.my.features.services.homarr = {
    enable = lib.mkEnableOption "Homarr Dashboard";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "ancoris.ovh";
      description = "Domain name for Homarr.";
    };
    ssoAuthority = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh/application/o/homarr/";
      description = "Authentik SSO authority issuer.";
    };
    ssoAuthorizeUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh/application/o/authorize";
      description = "Authentik OIDC authorize endpoint.";
    };
    ssoLogoutRedirectUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh/application/o/homarr/end-session/";
      description = "SSO Logout redirect URL.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.redis" ] config)

      {
        # 1. SOPS Secrets
        sops.secrets.homarr_auth_secret = { };
        sops.secrets.homarr_encryption_key = { };
        sops.secrets.homarr_oidc_client_secret = { };

        # 2. Template for environment variables based on latest Homarr docs
        sops.templates."homarr.env" = {
          content = ''
            # Security
            AUTH_SECRET=${config.sops.placeholder.homarr_auth_secret}
            SECRET_ENCRYPTION_KEY=${config.sops.placeholder.homarr_encryption_key}

            # URLs
            BASE_URL=https://${cfg.domain}
            NEXTAUTH_URL=https://${cfg.domain}

            # Redis (Using Mackaye's native redis)
            REDIS_IS_EXTERNAL=true
            REDIS_HOST=127.0.0.1
            REDIS_PORT=6379

            # Authentication Configuration
            AUTH_PROVIDERS=oidc
            AUTH_OIDC_AUTO_LOGIN=true
            AUTH_OIDC_CLIENT_NAME=Authentik
            AUTH_OIDC_CLIENT_ID=XNkHSIqbXSxj4I1s1P5aAjrHWjuKytniOE4uzA6L
            AUTH_OIDC_CLIENT_SECRET=${config.sops.placeholder.homarr_oidc_client_secret}
            AUTH_OIDC_ISSUER=${cfg.ssoAuthority}
            AUTH_OIDC_URI=${cfg.ssoAuthorizeUrl}
            AUTH_OIDC_SCOPE_OVERWRITE=openid email profile groups
            AUTH_OIDC_GROUPS_ATTRIBUTE=groups
            AUTH_LOGOUT_REDIRECT_URL=${cfg.ssoLogoutRedirectUrl}
            ADMIN_GROUP="Homarr Admins"
          '';
        };

        # 3. Create persistent directory with correct UID for the container
        systemd.tmpfiles.rules = [
          "d /var/lib/homarr 0755 1000 1000 -"
        ];

        # 4. Homarr Container
        virtualisation.oci-containers.containers."homarr" = {
          image = "ghcr.io/homarr-labs/homarr:dev";
          extraOptions = [ "--network=host" ];
          environmentFiles = [ config.sops.templates."homarr.env".path ];
          volumes = [
            "/var/lib/homarr:/appdata"
          ];
        };

        # 5. Reverse Proxy via Caddy
        my.endpoints.homarr = {
          host = config.networking.hostName;
          port = 7575;
          proxy = {
            enable = true;
            inherit (cfg) domain;
          };
        };
      }
    ]
  );
}
