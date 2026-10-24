{
  config,
  inputs,
  flake,
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
    adminSudo = true;
    opencodeSubscriptions = [
      {
        name = "subscription-3";
        apiKeySecret = "ai/opencode_api_key_3";
      }
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

  # The gateway host is the fleet's control plane, so it runs the GitOps
  # reconciler: it tracks main, deploys by drift, rolls back unhealthy hosts
  # and deploys itself last. Pushing to main is therefore the deploy button,
  # which is why main still needs review before a merge.
  #
  # Every host is in scope. An unreachable one - a laptop that is off, a phone
  # away from the mesh - is reported as unreachable and skipped, never treated
  # as a failed deployment.
  my.features.system.nod-sync = {
    enable = true;
    strategy = "canary";
    targets = [
      "cld-edge-01"
      "cld-ops-01"
      "hom-srv-01"
      "hom-wrk-01"
      "mob-nb-01"
    ];
    # The public entry point is deployed last: a canary that starts with the
    # ingress turns a rollout mistake into an outage.
    lastHosts = [ config.my.topology.ingressHost ];
    # The example provider runs in dry-run; the declaration lives in the
    # flake's `nod` output and is read by the daemon itself.
    reconcileProviders = true;
    extraEnvironmentFiles = [
      config.sops.templates."nod-cloudflare.env".path
      config.sops.templates."nod-authentik.env".path
    ];
    # The daemon reads these at startup; naming them here builds them with this
    # host, so a rollout cannot restart the daemon before its desired state exists.
    # Only file-backed declarations have a path to check at startup; an inline
    # declaration is already part of the flake evaluation.
    desiredStatePaths = builtins.filter (desired: !builtins.isAttrs desired) (
      map (provider: provider.desired) (
        builtins.filter (provider: provider ? desired) (builtins.attrValues flake.nod.providers)
      )
    );
  };

  # The provider's token is the same secret the access blueprint creates on the
  # edge host: SOPS is the single source, and the daemon reads it from the
  # environment, never from argv or the store.
  sops.secrets."services/authentik/nod_provider_token" = {
    sopsFile = ../../secrets/nod-provider.yaml;
    key = "token";
  };

  sops.templates."nod-authentik.env" = {
    content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."services/authentik/nod_provider_token"}
    '';
    restartUnits = [ "nod-sync.service" ];
  };

  my.features.system.networking.cloudflare.enable = true;

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
