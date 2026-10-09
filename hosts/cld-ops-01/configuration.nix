{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "cld-ops-01";

  # D11: the primary user is assigned, not discovered - alphabetical order must never
  # decide who owns a home directory.
  my.user.primary = "philipp";

  my.features.services.monitoring = {
    pipeline = {
      enable = true;
      role = "collector";
    };
  };

  my.features.services.attic.server.enable = true;

  my.features.services.crowdsec = {
    enable = true;
    role = "agent";
    excludeLogPatterns = [
      ".*cache.*"
      ".*ai.*"
    ];
  };

  my.features.services.authentik.outpost.proxy = {
    enable = true;
  };

  my.features.services.obsidian-livesync-bridge = {
    enable = true;
    # The instance name is the owner. The vault path, the run-as account and the CouchDB connection
    # therefore all follow from the defaults: the bridge owns an `obsidian-bridge` service account and
    # writes into its own vault directory, and the CouchDB URL derives from the topology domain.
    instances.philipp.enable = true;
  };

  my.features.services.searxng = {
    enable = true;
    port = 8888;
    # No domain here: the endpoint's subdomain plus the topology's root domain already derive
    # search.vyrx.de, which is what this line used to repeat.
    auth = true;
    openMeshFirewall = true;
    enableJsonApi = true;
  };

  # Personal gateway state and locally edited vaults require offsite backup. The repository
  # credential is shared with the edge; Restic retention groups snapshots by host and paths.
  my.features.system.backups.restic = {
    enable = true;
    environmentFile = "backups/restic/cld-edge-01";
    paths = [ ];
  };

  system.stateVersion = "24.11";
}
