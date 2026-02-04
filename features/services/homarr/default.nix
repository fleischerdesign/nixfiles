{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.homarr;
in
{
  options.my.features.services.homarr = {
    enable = lib.mkEnableOption "Homarr Dashboard";
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS Secrets
    sops.secrets.homarr_auth_secret = { };
    sops.secrets.homarr_encryption_key = { };
    sops.secrets.homarr_oidc_client_secret = { };

    # 2. Template for environment variables based on latest Homarr docs
    sops.templates."homarr.env" = {
      content = ''
        AUTH_SECRET=${config.sops.placeholder.homarr_auth_secret}
        SECRET_ENCRYPTION_KEY=${config.sops.placeholder.homarr_encryption_key}
        
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
        AUTH_OIDC_ISSUER=https://auth.ancoris.ovh/application/o/homarr/
        AUTH_OIDC_SCOPE_OVERWRITE="openid profile email groups"
        AUTH_OIDC_GROUPS_ATTRIBUTE=groups
        AUTH_OIDC_ADMIN_GROUP="Homarr Admins"
      '';
    };

    # 3. Create persistent directory with correct UID for the container
    systemd.tmpfiles.rules = [
      "d /var/lib/homarr 0755 1000 1000 -" 
    ];

    # 4. Homarr Container
    virtualisation.oci-containers.containers."homarr" = {
      image = "ghcr.io/homarr-labs/homarr:latest";
      extraOptions = [ "--network=host" ];
      environmentFiles = [ config.sops.templates."homarr.env".path ];
      volumes = [
        "/var/lib/homarr:/appdata"
      ];
    };

    # 5. Reverse Proxy via Caddy
    my.features.services.caddy.exposedServices = {
      "homarr" = {
        port = 7575;
        fullDomain = "ancoris.ovh";
      };
    };
  };
}
