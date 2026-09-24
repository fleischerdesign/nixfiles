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

  system.stateVersion = "24.11";
}
