{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.monitoring.grafana;
in
{
  options.my.features.services.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana Dashboard";
  };

  config = lib.mkIf cfg.enable {
    # SOPS Secrets for OIDC and ntfy
    sops.secrets.grafana_oidc_client_secret = { owner = "grafana"; };
    sops.secrets.grafana_oidc_client_id = { owner = "grafana"; };
    sops.secrets.grafana_ntfy_token = { }; # Definition from ntfy/default.nix

    # Template for Grafana environment variables
    sops.templates."grafana.env".content = ''
      GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${config.sops.placeholder.grafana_oidc_client_id}
      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder.grafana_oidc_client_secret}
      NTFY_TOKEN=${config.sops.placeholder.grafana_ntfy_token}
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
          role_attribute_path = "contains(groups, 'Grafana Admins') && 'Admin' || 'Viewer'";
        };
      };

      provision = {
        alerting = {
          contactPoints.settings.contactPoints = [
            {
              name = "ntfy";
              receivers = [
                {
                  uid = "ntfy-alerts";
                  type = "webhook";
                  settings = {
                    url = "https://ntfy.mky.ancoris.ovh/grafana-alerts?template=grafana";
                    httpMethod = "POST";
                    authorization_credentials = "$NTFY_TOKEN";
                  };
                }
              ];
            }
          ];
          policies.settings.policies = [
            {
              receiver = "ntfy";
              group_by = [ "alertname" ];
            }
          ];
          # Declarative Alert Rules
          rules.settings.groups = [
            {
              name = "Infrastructure";
              folder = "System";
              rules = [
                {
                  uid = "host-down";
                  title = "Host Down";
                  condition = "A";
                  for = "2m";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "prometheus-uid";
                      relativeTimeRange = { from = 600; to = 0; };
                      model = {
                        expr = "up == 0";
                        hide = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                  ];
                  annotations = {
                    summary = "Instance {{ $labels.instance }} has been down for more than 2 minutes.";
                  };
                }
                {
                  uid = "disk-space-low";
                  title = "Disk Space Low";
                  condition = "A";
                  for = "5m";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "prometheus-uid";
                      relativeTimeRange = { from = 600; to = 0; };
                      model = {
                        expr = "node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} * 100 < 10";
                        hide = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                  ];
                  annotations = {
                    summary = "Instance {{ $labels.instance }} has less than 10% free space on /.";
                  };
                }
              ];
            }
          ];
        };

        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "prometheus-uid";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            uid = "loki-uid";
            type = "loki";
            url = "http://localhost:3100";
          }
        ];
      };
    };

    systemd.services.grafana.serviceConfig.EnvironmentFile = [
      config.sops.templates."grafana.env".path
    ];

    my.features.services.caddy.exposedServices = {
      "grafana" = {
        port = 3000;
        subdomain = "grafana";
      };
    };
  };
}
