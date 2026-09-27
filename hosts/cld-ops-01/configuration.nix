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

  # Central AI Assistant Platform (Open-WebUI) on ai.vyrx.de
  my.features.services.open-webui = {
    enable = true;
  };

  my.features.services.authentik.outpost.proxy = {
    enable = true;
  };

  my.features.services.obsidian-livesync-bridge = {
    enable = true;
    instances.philipp = {
      enable = true;
      user = "obsidian-bridge";
      group = "obsidian-bridge";
      vaultPath = "/var/lib/obsidian-vaults/philipp";
      couchdb.url = "https://livesync.vyrx.de";
      couchdb.database = "obsidian-vault";
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

  # This host runs no Restic, and that is a decision rather than an omission (review decision D13): its
  # services hold no state that is not regenerable or reproduced elsewhere. The Attic binary cache and
  # the search index are rebuilt, and the LiveSync vault is a replica of the CouchDB database on
  # `cld-edge-01`, which is backed up. The backup contract refuses a host that declares restorable
  # state without saying either "back it up" or "this is why not".
  my.features.system.backups.restic.declined =
    "state on this host is regenerable or reproduced from the backed-up CouchDB on cld-edge-01";

  system.stateVersion = "24.11";
}
