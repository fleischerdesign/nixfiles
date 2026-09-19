{
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/server.nix
  ];

  networking.hostName = "hom-srv-01";

  my.user.extraGroups = [
    "networkmanager"
    "wheel"
    "media"
  ];

  # Features
  my = {
    features = {
      services = {
        home-assistant.enable = true;
        esphome.enable = true;
        mealie.enable = true;
        paperless.enable = true;
        prowlarr.enable = true;
        radarr.enable = true;
        sabnzbd.enable = true;
        sonarr.enable = true;
        jellyfin.enable = true;
        recyclarr.enable = true;
        blocky.enable = true;
        bazarr.enable = true;
        jellyseerr.enable = true;
        cloudflare-dyndns = {
          enable = true;
          domains = [ "srv.lan.vyrx.de" ];
        };
        klipper.enable = true;
        authentik.outpost.ldap = {
          enable = true;
          coreAddress = "http://${config.my.features.system.networking.topology.hosts.cld-edge-01.tailscaleIp}:9055";
        };
        monitoring = {
          pipeline = {
            enable = true;
            role = "collector";
          };
        };
        crowdsec = {
          enable = true;
          role = "agent";
        };
      };
      system = {
        networking = {
          gateway.enable = true;
          fritzbox.enable = true;
          tplink-ap.enable = true;
          tailscale = {
            subnetRouter = {
              enable = true;
              routes = [ "10.10.0.0/16" ];
            };
          };
        };
        backups.restic = {
          enable = true;
          paths = [
            "/var/lib"
            "/data/storage/docs"
          ];
          exclude = [
            "**/node_modules"
            "**/.cache"
            "/var/lib/docker"
            "/var/lib/jellyfin/metadata"
          ];
        };
      };
      dev.containers.enable = true;
    };
  };

  my.features.services.openclaw.node = {
    enable = true;
    instances = {
      philipp = {
        enable = true;
        displayName = "hom-srv-01";
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
        displayName = "hom-srv-01";
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
        displayName = "hom-srv-01";
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
        displayName = "hom-srv-01";
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
        displayName = "hom-srv-01";
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
