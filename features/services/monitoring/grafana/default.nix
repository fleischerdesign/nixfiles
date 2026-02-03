{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.monitoring.grafana;
in
{
  options.my.features.services.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana Dashboard";
  };

  config = lib.mkIf cfg.enable {
    # SOPS Secrets for OIDC
    sops.secrets.grafana_oidc_client_secret = { owner = "grafana"; };
    sops.secrets.grafana_oidc_client_id = { owner = "grafana"; };

    # Template to provide secrets as environment variables
    sops.templates."grafana.env".content = ''
      GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${config.sops.placeholder.grafana_oidc_client_id}
      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder.grafana_oidc_client_secret}
    '';

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "grafana.mky.ancoris.ovh";
          root_url = "https://grafana.mky.ancoris.ovh";
        };
        
        # OIDC Authentication with Authentik
        "auth.generic_oauth" = {
          enabled = true;
          name = "Authentik";
          allow_sign_up = true;
          client_id = "$__ENV{GF_AUTH_GENERIC_OAUTH_CLIENT_ID}";
          client_secret = "$__ENV{GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}";
          scopes = "openid profile email";
          auth_url = "https://auth.ancoris.ovh/application/o/authorize/";
          token_url = "https://auth.ancoris.ovh/application/o/token/";
          api_url = "https://auth.ancoris.ovh/application/o/userinfo/";
          # Map Authentik groups to Grafana roles
          role_attribute_path = "contains(groups, 'Grafana Admins') && 'Admin' || 'Viewer'";
        };
      };

      provision = {
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://localhost:3100";
          }
        ];
      };
    };

    # Load the environment file into the Grafana service
    systemd.services.grafana.serviceConfig.EnvironmentFile = [
      config.sops.templates."grafana.env".path
    ];

    # Reverse Proxy
    my.features.services.caddy.exposedServices = {
      "grafana" = {
        port = 3000;
        subdomain = "grafana";
      };
    };
  };
}
