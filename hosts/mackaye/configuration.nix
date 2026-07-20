{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "mackaye";

  # Features
  my.features.services.caddy.baseDomain = "mky.ancoris.ovh";

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
  my.features.services.couchdb.enable = true;

  my.features.services.ntfy.enable = true;
  my.features.system.backups.restic = {
    enable = true;
    environmentFile = "restic_env_mackaye";
  };

  system.stateVersion = "24.11";
}
