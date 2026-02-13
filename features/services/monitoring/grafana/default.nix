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

        log = {
          level = "info";
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
          rules.settings.groups = [
            {
              name = "Infrastructure";
              folder = "System";
              interval = "60s";
              rules = [
                {
                  uid = "infra-host-down-v3";
                  title = "Host Down";
                  condition = "C";
                  for = "2m";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "PBFA97CFB590B2093";
                      relativeTimeRange = { from = 600; to = 0; };
                      model = { 
                        # Capture both node_mackaye and node_strummer
                        expr = "up{job=~\"node_.*\"}"; 
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "-100";
                      model = { expression = "A"; type = "reduce"; reducer = "last"; };
                    }
                    {
                      refId = "C";
                      datasourceUid = "-100";
                      model = { expression = "$B == 0"; type = "math"; };
                    }
                  ];
                  annotations = {
                    summary = "Instance {{ $labels.instance }} has been down for more than 2 minutes.";
                  };
                }
                {
                  uid = "infra-disk-space-v3";
                  title = "Disk Space Low";
                  condition = "C";
                  for = "5m";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "PBFA97CFB590B2093";
                      relativeTimeRange = { from = 600; to = 0; };
                      model = { 
                        expr = "(node_filesystem_avail_bytes{fstype!~\"tmpfs|fuse.lxcfs|cgroup|none\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|fuse.lxcfs|cgroup|none\"} * 100)";
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "-100";
                      model = { expression = "A"; type = "reduce"; reducer = "last"; };
                    }
                    {
                      refId = "C";
                      datasourceUid = "-100";
                      model = { expression = "$B < 10"; type = "math"; };
                    }
                  ];
                  annotations = {
                    summary = "Instance {{ $labels.instance }} device {{ $labels.device }} mounted on {{ $labels.mountpoint }} has less than 10% free space.";
                  };
                }
                {
                  uid = "infra-high-ram-v2";
                  title = "High Memory Usage";
                  condition = "C";
                  for = "5m";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "PBFA97CFB590B2093";
                      relativeTimeRange = { from = 600; to = 0; };
                      model = { expr = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)"; };
                    }
                    {
                      refId = "B";
                      datasourceUid = "-100";
                      model = { expression = "A"; type = "reduce"; reducer = "last"; };
                    }
                    {
                      refId = "C";
                      datasourceUid = "-100";
                      model = { expression = "$B > 95"; type = "math"; };
                    }
                  ];
                  annotations = {
                    summary = "Instance {{ $labels.instance }} has more than 95% RAM usage.";
                  };
                }
                {
                  uid = "infra-systemd-failed-v2";
                  title = "Systemd Service Failed";
                  condition = "C";
                  for = "1m";
                  data = [
                    {
                      refId = "A";
                      datasourceUid = "PBFA97CFB590B2093";
                      relativeTimeRange = { from = 600; to = 0; };
                      model = { expr = "node_systemd_unit_state{state=\"failed\"}"; };
                    }
                    {
                      refId = "B";
                      datasourceUid = "-100";
                      model = { expression = "A"; type = "reduce"; reducer = "last"; };
                    }
                    {
                      refId = "C";
                      datasourceUid = "-100";
                      model = { expression = "$B == 1"; type = "math"; };
                    }
                  ];
                  annotations = {
                    summary = "Systemd service {{ $labels.name }} on {{ $labels.instance }} is in failed state.";
                  };
                }
              ];
            }
          ];
        };

        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "PBFA97CFB590B2093"; 
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            uid = "P8E80F9AEF21F6940";
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