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

  networking.hostName = "strummer";

  # Features
  my = {
    features = {
      services = {
        caddy = {
          enable = true;
          baseDomain = "fls.ancoris.ovh";
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
          domains = [ "fls.ancoris.ovh" ];
        };
        klipper.enable = true;
        authentik.outpost.proxy.enable = true;
        authentik.outpost.ldap = {
          enable = true;
          coreAddress = "http://${config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp}:9055";
          tokenSecretName = "authentik_outpost_ldap_token_strummer";
        };
        monitoring.node-exporter.enable = true;
        monitoring.alloy = {
          enable = true;
          lokiHost = config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp;
        };
        monitoring.blackbox-exporter.enable = true;
        crowdsec = {
          enable = true;
          role = "agent";
        };
      };
      system = {
        networking.tailscale = {
          enable = true;
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
      dev = {
        nixvim.enable = true;
        containers = {
          enable = true;
          users = [ "philipp" ];
        };
      };
    };

    endpoints = {
      home-assistant.subdomain = "hass";
      esphome = {
        subdomain = "esphome";
        auth = true;
      };
      mealie.subdomain = "mealie";
      paperless.subdomain = "paperless";
      prowlarr = {
        subdomain = "prowlarr";
        auth = true;
      };
      radarr = {
        subdomain = "radarr";
        auth = true;
      };
      sabnzbd = {
        subdomain = "sabnzbd";
        auth = true;
      };
      sonarr = {
        subdomain = "sonarr";
        auth = true;
      };
      jellyfin.subdomain = "jellyfin";
      bazarr = {
        subdomain = "bazarr";
        auth = true;
      };
      jellyseerr.subdomain = "seerr";
      mainsail = {
        subdomain = "mainsail";
        auth = true;
      };
      moonraker = {
        subdomain = "moonraker";
        auth = true;
      };
      mainsail-cam.subdomain = "cam.moonraker";
    };
  };

  system.stateVersion = "24.11";
}
