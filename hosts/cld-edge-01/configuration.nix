{
  inputs,
  config,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "cld-edge-01";

  my.features.system.networking.tailscale.acceptRoutes = true;
  my.features.system.networking.cloudflare.enable = true;

  # Ingress alias for the OpenClaw family mesh. The redirect itself is served by
  # cld-ops-01 as a host-level Caddy vhost; only the record is declared here, so
  # the DNS projection stays free of hand-maintained service wildcards.
  my.features.system.networking.cloudflare.records = [
    {
      name = "ai";
      type = "CNAME";
      content = "ops.${config.my.topology.domain}";
      comment = "OpenClaw family mesh alias -> cld-ops-01";
    }
  ];
  my.features.system.common.geoip.enable = true;

  my.features.services.monitoring = {
    pipeline = {
      enable = true;
      role = "full";
    };
  };
  my.features.services.crowdsec.enable = true;
  my.features.services.crowdsec.role = "master";

  my.features.services.postgresql.enable = true;
  my.features.services.redis.enable = true;
  my.features.services.authentik.server.enable = true;
  my.features.services.authentik.outpost.ldap = {
    enable = true;
    coreAddress = "http://127.0.0.1:9055";
  };

  my.features.services.vyrx-landing.enable = true;
  my.features.services.portfolio.enable = true;
  my.features.services.salus.enable = true;
  my.features.services.obsidian-livesync.enable = true;

  my.features.services.ntfy.enable = true;
  my.features.system.backups.restic = {
    enable = true;
  };

  my.features.services.openclaw.node = {
    enable = true;
    instances = {
      philipp = {
        enable = true;
        displayName = "cld-edge-01";
        gateway = {
          host = config.my.features.system.networking.topology.hosts.cld-ops-01.tailscaleIp;
          port = 18789;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18790;
        sessionHosting.enable = true;
      };

      katja = {
        enable = true;
        displayName = "cld-edge-01";
        gateway = {
          host = config.my.features.system.networking.topology.hosts.cld-ops-01.tailscaleIp;
          port = 18791;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18794;
        sessionHosting.enable = true;
      };

      lilly = {
        enable = true;
        displayName = "cld-edge-01";
        gateway = {
          host = config.my.features.system.networking.topology.hosts.cld-ops-01.tailscaleIp;
          port = 18792;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18795;
        sessionHosting.enable = true;
      };

      kai = {
        enable = true;
        displayName = "cld-edge-01";
        gateway = {
          host = config.my.features.system.networking.topology.hosts.cld-ops-01.tailscaleIp;
          port = 18793;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18796;
        sessionHosting.enable = true;
      };

      rieke = {
        enable = true;
        displayName = "cld-edge-01";
        gateway = {
          host = config.my.features.system.networking.topology.hosts.cld-ops-01.tailscaleIp;
          port = 18794;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18797;
        sessionHosting.enable = true;
      };
    };
  };

  system.stateVersion = "24.11";
}
