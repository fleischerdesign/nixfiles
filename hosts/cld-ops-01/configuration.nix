{
  config,
  inputs,
  flake,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.nod.nixosModules.fleet
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
    model = "openai/gpt-6.1-terra";
    subagentModel = "opencode-go/deepseek-v4.1-flash";
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
      map (provider: provider.desired) (builtins.attrValues config.services.nod.providers)
    );
  };

  # The fleet declaration, typed by nod's `services.nod` module. The daemon
  # reads `config.services.nod.fleet` through the flake output; the provider
  # entries below are the only hand-written part, and every field is checked at
  # evaluation.

  # A `command` string does not put a binary in the closure: nod spawns each provider itself, and
  # only packages on this host's PATH can be spawned. Without this list the cloudflare provider
  # could not start at all, so no service record was ever reconciled.
  systemd.services.nod-sync.path = [
    inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.nod-provider-cloudflare
    inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.nod-provider-example
  ];

  services.nod.providers = {
    example = {
      command = "${
        inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.nod-provider-example
      }/bin/nod-provider-example";
      settings.state = "/var/lib/nod/example-state.json";
      desired = "${pkgs.writeText "nod-example-desired.json" (
        builtins.toJSON {
          resources = [
            {
              kind = "example.record";
              id = "demo";
              attributes.value = "dry-run";
            }
          ];
        }
      )}";
      apply = true;
      interval = 300;
      policy = {
        # The example record is never deleted, and this provider may not
        # delete at all: a declaration that wants to remove records has to
        # say so explicitly.
        protect = [ "demo" ];
        maxDeletions = 0;
      };
    };

    # The real zone. The declaration lives on the control-plane host, which also
    # projects it for the observer; the daemon reads the same store path. nod is
    # the only writer.
    cloudflare = {
      command = "${
        inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.nod-provider-cloudflare
      }/bin/nod-provider-cloudflare";
      settings = {
        zone = config.my.features.system.networking.cloudflare.domain;
        token_env = "CLOUDFLARE_API_TOKEN";
      };
      desired = config.my.features.system.networking.cloudflare.nodDesiredStateFile;
      apply = true;
      interval = 300;
      timeout = 120;
      env = [ "CLOUDFLARE_API_TOKEN" ];
      policy = {
        # The apex and the mail/delegation records are never deleted; one
        # deletion per run is enough for a deliberate removal.
        protect = [
          "A:vyrx.de"
          "MX:*"
          "NS:*"
        ];
        maxDeletions = 1;
      };
    };

    # Authentik's directory and proxy stack. The provider is the only writer.
    authentik = {
      command = "${
        inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.nod-provider-authentik
      }/bin/nod-provider-authentik";
      settings = {
        url = "http://10.10.100.1:9055";
        token_env = "AUTHENTIK_TOKEN";
        # The fleet's existing ownership marker; another installation chooses
        # its own key and value.
        marker_key = "vyrx";
        marker_value = "owned";
      };
      desired =
        flake.nixosConfigurations.cld-edge-01.config.my.features.services.authentik.server.nodDesired;
      apply = true;
      interval = 300;
      timeout = 60;
      env = [ "AUTHENTIK_TOKEN" ];
      policy = {
        # The bootstrap and default groups are never deleted, and this provider
        # may not delete at all: a declaration that wants to remove a group has
        # to say so explicitly.
        protect = [
          "authentik Admins"
          "authentik Read-only"
          "authentik Users"
          "nod-provider"
        ];
        maxDeletions = 0;
      };
    };
  };

  # The provider's token is the same secret the access blueprint creates on the
  # edge host: SOPS is the single source, and the daemon reads it from the
  # environment, never from argv or the store.
  sops.secrets = lib.mergeAttrsList [
    # The OIDC client secrets the reconciler must be able to present when it
    # creates a provider on a fresh install. This host already holds a
    # superuser token, which can read every client secret through the API, so
    # rendering them here widens no boundary - it only removes the second
    # writer the blueprint used to be.
    (lib.genAttrs
      (builtins.attrValues flake.nixosConfigurations.cld-edge-01.config.my.features.services.authentik.server.nodOidcSecrets)
      (_: { })
    )
    # The signing keypair's two PEMs. The declaration names these files; the
    # provider reads them once, on create, and never reports them (ADR-044).
    # The secret *name* is a path, the file holds two flat keys, so each secret
    # names the key it selects.
    {
      ${flake.nixosConfigurations.cld-edge-01.config.my.features.services.authentik.server.oidcSigningKeySecrets.certificate} =
        {
          sopsFile = ../../secrets/authentik-signing.yaml;
          key = "certificate";
          mode = "0400";
        };
      ${flake.nixosConfigurations.cld-edge-01.config.my.features.services.authentik.server.oidcSigningKeySecrets.key} =
        {
          sopsFile = ../../secrets/authentik-signing.yaml;
          key = "key";
          mode = "0400";
        };
    }
    {
      "services/authentik/nod_provider_token" = {
        sopsFile = ../../secrets/nod-provider.yaml;
        key = "token";
      };
    }
  ];

  sops.templates."nod-authentik.env" = {
    content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."services/authentik/nod_provider_token"}
    ''
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        env: path: "${env}=${config.sops.placeholder.${path}}"
      ) flake.nixosConfigurations.cld-edge-01.config.my.features.services.authentik.server.nodOidcSecrets
    )
    + "\n";
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
      couchdb.passphraseSecret = "services/storage/couchdb_obsidian_passphrase";
      # Plugin state (project serials, pinned tasks, trackers) rides along as `i:` documents;
      # the bridge materialises it so the agent can read the app's own state, not just content.
      couchdb.includeInternal = [ ".obsidian/plugins/operon/state/**" ];
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
