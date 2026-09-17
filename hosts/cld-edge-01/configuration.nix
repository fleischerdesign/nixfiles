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

  # Features
  my.features.services.caddy.baseDomain = "edge.vyrx.de";

  my.features.system.networking.tailscale.acceptRoutes = true;
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
    tokenSecretName = "authentik_outpost_ldap_token_mackaye";
  };

  my.features.services.portfolio.enable = true;
  my.features.services.salus.enable = true;
  my.features.services.obsidian-livesync.enable = true;

  my.features.services.ntfy.enable = true;
  my.features.system.backups.restic = {
    enable = true;
    environmentFile = "restic_env_mackaye";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
        sessionHosting.enable = true;
      };
    };
  };

  system.stateVersion = "24.11";
}
