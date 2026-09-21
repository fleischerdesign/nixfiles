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
        # The resolver with plane-correct views replaced blocky and serves port 53 itself.
        # Blocky stays in the tree, disabled, as the rollback.
        blocky.enable = false;
        dns = {
          enable = true;
          # The home door: DNS-over-TLS, so a client that follows the resolver by name (a
          # phone's private DNS setting) is answered here while it is at home.
          dot = true;
        };
        bazarr.enable = true;
        jellyseerr.enable = true;
        klipper.enable = true;
        authentik.outpost.ldap = {
          enable = true;
          coreAddress = "http://${config.my.topology.hosts.cld-edge-01.wireguardIpv4}:9055";
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
          # TEMPORARY (cutover): the FRITZ!Box still serves DHCP on the old LAN - it rejected the
          # TR-064 address move (UPnP 402, argument format still to be determined), so it has not
          # moved yet. Kea must stay off until it has, or two DHCP servers answer on one L2
          # segment. Flip to true together with the box move (docs/operations.md §10 Step 4).
          gateway = {
            enable = true;
            enableDhcp = true;
          };
          fritzbox = {
            enable = true;
            # TR-064 needs a dedicated FRITZ!Box user from FRITZ!OS 7.24 on; the password-only
            # UI login no longer works over the API (the old dslf-config shortcut is gone).
            user = "fritz1498";
          };
          tplink-ap.enable = true;
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
          host = config.my.topology.hosts.cld-ops-01.wireguardIpv4;
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
          host = config.my.topology.hosts.cld-ops-01.wireguardIpv4;
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
          host = config.my.topology.hosts.cld-ops-01.wireguardIpv4;
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
          host = config.my.topology.hosts.cld-ops-01.wireguardIpv4;
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
          host = config.my.topology.hosts.cld-ops-01.wireguardIpv4;
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
