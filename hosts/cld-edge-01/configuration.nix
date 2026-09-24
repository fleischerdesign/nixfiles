{
  inputs,
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

  my.features.system.networking.cloudflare.enable = true;

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
  # The public door of the resolver: this host declares the resolver's name as a public
  # endpoint (DNS record + firewall) and terminates DNS-over-TLS for roaming clients.
  my.features.services.dns = {
    enable = true;
    publicEntry = true;
    # The public door terminates DNS-over-TLS itself, on the ingress address.
    dot = true;
  };
  my.features.services.obsidian-livesync.enable = true;

  my.features.services.ntfy.enable = true;
  my.features.system.backups.restic = {
    enable = true;
  };

  system.stateVersion = "24.11";
}
