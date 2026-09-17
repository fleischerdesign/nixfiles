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
        caddy = {
          baseDomain = "srv.lan.vyrx.de";
        };
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
        authentik.outpost.proxy = {
          enable = true;
          tokenSecretName = "authentik_outpost_proxy_token_strummer";
        };
        authentik.outpost.ldap = {
          enable = true;
          coreAddress = "http://${config.my.features.system.networking.topology.hosts.cld-edge-01.tailscaleIp}:9055";
          tokenSecretName = "authentik_outpost_ldap_token_strummer";
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
        networking.tailscale = {
          subnetRouter = {
            enable = true;
            routes = [ "192.168.178.0/24" ];
          };
        };
        backups.restic = {
          enable = true;
          environmentFile = "restic_env_strummer";
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

    endpoints = {
      home-assistant.proxy.subdomain = "hass";
      home-assistant.proxy.enable = true;
      home-assistant.directAccess.enable = true;

      esphome.proxy = {
        enable = true;
        subdomain = "esphome";
        auth = true;
      };

      mealie.proxy.subdomain = "mealie";
      mealie.proxy.enable = true;

      paperless.proxy.subdomain = "paperless";
      paperless.proxy.enable = true;

      prowlarr.proxy = {
        enable = true;
        subdomain = "prowlarr";
        auth = true;
      };

      radarr.proxy = {
        enable = true;
        subdomain = "radarr";
        auth = true;
      };

      sabnzbd.proxy = {
        enable = true;
        subdomain = "sabnzbd";
        auth = true;
      };

      sonarr.proxy = {
        enable = true;
        subdomain = "sonarr";
        auth = true;
      };

      jellyfin.proxy.subdomain = "jellyfin";
      jellyfin.proxy.enable = true;

      bazarr.proxy = {
        enable = true;
        subdomain = "bazarr";
        auth = true;
      };

      jellyseerr.proxy.subdomain = "seerr";
      jellyseerr.proxy.enable = true;

      mainsail.proxy = {
        subdomain = "mainsail";
        auth = true;
      };

      moonraker.proxy = {
        subdomain = "moonraker";
        auth = true;
      };

      mainsail-cam.proxy.subdomain = "cam.moonraker";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
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
        passwordSecret = "openclaw_gateway_password";
        sessionHosting.enable = true;
      };
    };
  };

  system.stateVersion = "24.11";
}
