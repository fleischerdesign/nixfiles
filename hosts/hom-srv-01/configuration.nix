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
          # The cutover is done: the FRITZ!Box's own DHCP is off - verified over TR-064, not
          # assumed (`DHCP server current=False desired=False`) - so Kea is the only DHCP server
          # on the segment and serves every zone. The box stays the modem; the fritzbox
          # reconciler keeps its DHCP toggle, DNS setting and port forwards neutral and never
          # touches its LAN address or subnet (docs/architecture.md 3.3). The one diff it still
          # reports is the box's DHCP range, which is inert while its DHCP is off.
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

  system.stateVersion = "24.11";
}
