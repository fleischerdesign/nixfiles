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

  my.features.services.openclaw.gateway = {
    enable = true;
    opencodeSubscriptions = [
      {
        name = "subscription-2";
        apiKeySecret = "ai/opencode_api_key_2";
      }
      {
        name = "subscription-1";
        apiKeySecret = "ai/opencode_api_key";
      }
    ];
  };

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
    # The instance name is the owner and the CouchDB URL derives from the topology domain. This
    # instance serves the gateway alone, so it runs with the gateway's identity and mirrors into the
    # gateway's own state instead of a second service account: no shared group, and a note the agent
    # writes stays readable to the bridge because writer and reader are the same account. The vault
    # is a replica of CouchDB either way, which is what keeps it out of the backup.
    instances.philipp = {
      enable = true;
      user = "openclaw";
      group = "openclaw";
      vaultPath = "/var/lib/openclaw/vaults/philipp";
    };
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
