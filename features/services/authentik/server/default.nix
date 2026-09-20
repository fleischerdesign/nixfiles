{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.authentik.server;

  # Constructors for blueprint entries. They belong to this feature, not to the framework: they encode
  # authentik's rules, and they exist so that a model name, a reference kind and the placement of a field
  # cannot be mistyped into an entry that is silently skipped.
  blueprintLib = import ../lib/blueprint.nix { inherit lib; };

  # Blueprint application is asynchronous upstream: the API's apply endpoint and the hourly discovery both
  # only queue a task. The unit below queues the same task and then waits for the effect, so a deploy is
  # finished when the objects exist, not when a file was written.
  blueprintsApplyTimeoutSeconds = 900;

  # Blueprint data: discovery, checks, the four documents and the directory they assemble into. It lives
  # in its own module because it has its own owner - authentik's object model and the fleet contracts.
  blueprints = import ./blueprints.nix {
    inherit
      config
      lib
      pkgs
      blueprintLib
      ;
  };

  # What the feature depends on, checked after every apply. A successful apply is not the same as a world
  # that matches the declaration: the object permission that lets a consumer read the directory lives in the
  # database rather than in a blueprint, so a fresh install would come up looking healthy while Jellyfin could
  # not search. These are the invariants the design rests on, and a deploy that breaks one must fail.

  # Apply path: queue the task and wait for the effect, then check the invariants above. It asserts on
  # `last_applied` rather than on `status` alone: status describes the last attempt, so a failed apply leaves
  # the previous value behind and a blueprint can read `successful` while the object it declares does not
  # exist.
  blueprintsApplyScript = pkgs.writeText "authentik-apply-blueprints.py" ''
    import sys
    import time

    from authentik.blueprints.models import BlueprintInstance
    from authentik.blueprints.v1.tasks import apply_blueprint
    from authentik.core.models import Application, User
    from authentik.flows.models import Flow, FlowStageBinding
    from authentik.policies.models import PolicyBinding
    from authentik.providers.ldap.models import LDAPProvider

    EXPECTED = ${builtins.toJSON blueprints.expectations}

    instances = list(BlueprintInstance.objects.filter(enabled=True))
    if not instances:
        print("no enabled blueprint instances")
        sys.exit(0)

    before = {i.name: i.last_applied for i in instances}
    deadline = time.monotonic() + ${toString blueprintsApplyTimeoutSeconds}

    def send(targets):
        for instance in targets:
            apply_blueprint.send_with_options(args=(instance.pk,), rel_obj=instance)

    def settle(targets):
        """Wait until every target reports a fresh, successful apply; return the names still waiting."""
        while True:
            time.sleep(3)
            waiting = []
            for instance in targets:
                instance.refresh_from_db()
                if instance.status == "error":
                    continue
                previous = before[instance.name]
                if not (
                    instance.last_applied is not None
                    and instance.status == "successful"
                    and (previous is None or instance.last_applied > previous)
                ):
                    waiting.append(instance.name)
            if not waiting:
                return []
            if time.monotonic() > deadline:
                return waiting

    # The order across blueprint files is not guaranteed by authentik, so the dependency is declared with the
    # meta model rather than retried here: `ldapDependencies` makes the outposts blueprint apply the
    # consumers blueprint first, because the provider carries a permission for the consumer's roles. A deploy
    # that breaks such a dependency fails loudly instead of being papered over by a second pass.
    send(instances)
    waiting = settle(instances)

    if waiting:
        print("FAILED apply, still not settled: " + ", ".join(sorted(waiting)))
        sys.exit(1)

    failures = []

    def expect(description, condition):
        if not condition:
            failures.append(description)

    for slug in EXPECTED["applicationsWithoutBindings"]:
        application = Application.objects.filter(slug=slug).first()
        expect(
            f"application {slug} exists",
            application is not None,
        )
        if application is not None:
            count = PolicyBinding.objects.filter(target=application).count()
            expect(f"application {slug} has no policy binding (found {count})", count == 0)

    for slug, expected in EXPECTED["flowStageBindings"].items():
        flow = Flow.objects.filter(slug=slug).first()
        expect(f"flow {slug} exists", flow is not None)
        if flow is not None:
            count = FlowStageBinding.objects.filter(target=flow).count()
            expect(f"flow {slug} has {expected} stage bindings (found {count})", count == expected)

    for slug in EXPECTED["flowsWithoutBindings"]:
        flow = Flow.objects.filter(slug=slug).first()
        if flow is not None:
            count = PolicyBinding.objects.filter(target=flow).count()
            expect(f"flow {slug} has no policy binding (found {count})", count == 0)

    provider = LDAPProvider.objects.first()
    expect("an LDAP provider exists", provider is not None)
    for username in EXPECTED["searchFullDirectoryAccounts"]:
        user = User.objects.filter(username=username).first()
        expect(f"service account {username} exists", user is not None)
        if user is not None and provider is not None:
            expect(
                f"{username} may search the full directory",
                user.has_perm("search_full_directory", provider)
                or user.has_perm("authentik_providers_ldap.search_full_directory"),
            )

    if failures:
        for failure in failures:
            print(f"FAILED invariant: {failure}")
        sys.exit(1)

    print("applied and verified: " + ", ".join(sorted(before)))
    sys.exit(0)
  '';

  # The directory's structure comes from the fleet-wide contract, never from a literal here.

  # One rule for the name of every consumer's service account, taken from the directory contract so
  # that a consumer on another host composes exactly the same DN without reading anything of ours.
  authentikPackage = pkgs.authentik;

  # Single listener for the API *and* the embedded proxy outpost (authentik serves
  # both on the same HTTP listener). Kept here so every projection stays in sync.
  listenHttpPort = 9055;

  # Only the trusted ingress networks may inject authentication headers.
  trustedProxyCidrs = lib.concatStringsSep "," (
    [
      "127.0.0.0/8"
      "100.64.0.0/10"
    ]
    ++ lib.optional (config.my.topology.subnets ? mesh) config.my.topology.subnets.mesh.cidr
  );

  # Cluster-wide endpoint discovery across all hosts for forward-auth proxy services
  # Apply path: blueprint changes ship inside the system closure. `nod switch
  # cld-edge-01` installs the new blueprints.dir; the service
  # restartTriggers pick it up and the worker discovers and applies the blueprints
  # natively. There is intentionally no separate API push target.
in
{
  options.my.features.services.authentik.server = {
    enable = lib.mkEnableOption "Authentik Identity Provider (Server)";
    adminEmail = lib.mkOption {
      type = lib.types.str;
      default = "philipp@vyrx.de";
      description = "Email address applied to the bootstrapped `akadmin` account.";
    };
    embeddedOutpostAddress = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        let
          serverHosts = lib.filter (
            hostName:
            (blueprints.flakeConfigurations.${hostName}.config.my.features.services.authentik.server.enable
              or false
            )
          ) (builtins.attrNames blueprints.flakeConfigurations);
          serverHost = if serverHosts == [ ] then null else builtins.head serverHosts;
        in
        if serverHost == null || serverHost == config.networking.hostName then
          "127.0.0.1:${toString listenHttpPort}"
        else
          "${config.my.topology.hosts.${serverHost}.wireguardIpv4}:${toString listenHttpPort}";
      description = "Address of the central embedded outpost as reachable from this host.";
    };
    blueprintsDir = lib.mkOption {
      type = lib.types.package;
      default = blueprints.dir;
      readOnly = true;
      description = "Compiled directory of static and dynamically compiled Authentik blueprints";
    };
  };

  config = lib.mkIf cfg.enable {
    # The directory's structure is not projected from here: the provider and its consumers usually run
    # on different hosts, so anything a consumer needs must live in the directory contract itself.

    # 1. User & Group
    users.users.authentik = {
      isSystemUser = true;
      group = "authentik";
      home = "/var/lib/authentik";
      createHome = true;
    };
    users.groups.authentik = { };

    # The service WorkingDirectory/home must survive a database wipe: createHome is
    # only honoured on user creation, so ensure it declaratively on every activation.
    systemd.tmpfiles.rules = [
      "d /var/lib/authentik 0700 authentik authentik -"
    ];

    # 2. Authentik Server Service
    systemd.services.authentik-server = {
      description = "Authentik Server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "postgresql.service"
        "redis.service"
      ];

      serviceConfig = {
        ExecStart = "${lib.getExe authentikPackage} server";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        # Environment
        EnvironmentFile = [
          config.sops.secrets."services/authentik/core_env".path
          config.sops.templates."authentik_secrets.env".path
        ];
        Environment = [
          "AUTHENTIK_REDIS__HOST=127.0.0.1"
          "AUTHENTIK_REDIS__PORT=6379"
          "AUTHENTIK_POSTGRESQL__HOST=/run/postgresql"
          "AUTHENTIK_POSTGRESQL__NAME=authentik"
          "AUTHENTIK_POSTGRESQL__USER=authentik"
          # The embedded proxy outpost and the API share this listener.
          "AUTHENTIK_LISTEN__HTTP=0.0.0.0:${toString listenHttpPort}"
          "AUTHENTIK_LISTEN__METRICS=0.0.0.0:9300"
          "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=${trustedProxyCidrs}"
          "AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true"
          "AUTHENTIK_AVATARS=gravatar"
          "AUTHENTIK_EVENTS__CONTEXT_PROCESSORS__GEOIP=/var/lib/GeoIP/GeoLite2-City.mmdb"
          # Populate the bootstrap admin on first start; the matching
          # AUTHENTIK_BOOTSTRAP_PASSWORD_HASH lives in the core_env secret.
          "AUTHENTIK_BOOTSTRAP_EMAIL=${cfg.adminEmail}"
          "AUTHENTIK_BLUEPRINTS_DIR=${cfg.blueprintsDir}"
        ];
        Restart = "always";
      };
      restartTriggers = [ cfg.blueprintsDir ];
    };

    # 3. Authentik Worker Service
    systemd.services.authentik-worker = {
      description = "Authentik Worker";
      wantedBy = [ "multi-user.target" ];
      after = [
        "postgresql.service"
        "redis.service"
      ];

      serviceConfig = {
        ExecStart = "${lib.getExe authentikPackage} worker";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        EnvironmentFile = [
          config.sops.secrets."services/authentik/core_env".path
          config.sops.templates."authentik_secrets.env".path
        ];
        Environment = [
          "AUTHENTIK_REDIS__HOST=127.0.0.1"
          "AUTHENTIK_REDIS__PORT=6379"
          "AUTHENTIK_POSTGRESQL__HOST=/run/postgresql"
          "AUTHENTIK_POSTGRESQL__NAME=authentik"
          "AUTHENTIK_POSTGRESQL__USER=authentik"
          # The worker exposes its own metrics listener; keep it off the server's
          # scrape port (9300), otherwise the second bind fails and the worker
          # supervisor tears the task runner down on startup.
          "AUTHENTIK_LISTEN__METRICS=127.0.0.1:9301"
          # Serialize blueprint application. On a fresh install authentik applies all
          # blueprints concurrently; the upstream default flow blueprints then
          # deadlock on authentik_flows_stage (PostgreSQL), and our application
          # blueprints additionally apply those same flow blueprints via
          # metaapplyblueprint. One thread removes the lock-order inversion
          # deterministically. The documented "<2 not recommended" caveat targets
          # throughput on scaled-out replicas; this instance is single-replica.
          "AUTHENTIK_WORKER__THREADS=1"
          "AUTHENTIK_BOOTSTRAP_EMAIL=${cfg.adminEmail}"
          "AUTHENTIK_BLUEPRINTS_DIR=${cfg.blueprintsDir}"
        ];
        Restart = "always";
      };
      restartTriggers = [ cfg.blueprintsDir ];
    };

    # Blueprint application, tied to the deployment.
    #
    # The documented trigger for file-based blueprints is a modification event in the blueprint directory;
    # under Nix that directory is an immutable store path a deploy replaces wholesale, so no file inside it
    # is ever modified and the watcher cannot fire. Measured: after a deploy that changed the blueprints, the
    # worker started, applied nothing, and the objects appeared only at the next hourly discovery - which is
    # why a blueprint could read `successful` for a whole hour while the object it declared did not exist.
    #
    # This unit uses the mechanism this repository already relies on for "act when the deployment changed":
    # restartTriggers content-hashes the blueprints directory into the unit, so systemd starts it exactly
    # when a deploy produced different blueprints - and on boot, where authentik applies nothing by itself.
    # It queues the task the API's apply endpoint queues and waits for every instance to settle.
    systemd.services.authentik-blueprints-apply = {
      description = "Apply the generated authentik blueprints";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik-worker.service" ];
      requires = [ "authentik-worker.service" ];

      restartTriggers = [ cfg.blueprintsDir ];

      serviceConfig = {
        Type = "oneshot";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        TimeoutStartSec = toString (blueprintsApplyTimeoutSeconds + 60);
        EnvironmentFile = [
          config.sops.secrets."services/authentik/core_env".path
          config.sops.templates."authentik_secrets.env".path
        ];
        Environment = [
          "AUTHENTIK_REDIS__HOST=127.0.0.1"
          "AUTHENTIK_REDIS__PORT=6379"
          "AUTHENTIK_POSTGRESQL__HOST=/run/postgresql"
          "AUTHENTIK_POSTGRESQL__NAME=authentik"
          "AUTHENTIK_POSTGRESQL__USER=authentik"
          "AUTHENTIK_BOOTSTRAP_EMAIL=${cfg.adminEmail}"
          "AUTHENTIK_BLUEPRINTS_DIR=${cfg.blueprintsDir}"
        ];
        ExecStart = "${lib.getExe authentikPackage} shell";
        StandardInput = "file:${blueprintsApplyScript}";
      };
    };

    # 4. Inversion of Control: Declare PostgreSQL requirement
    my.contracts.consumes.authentik.postgresql.main = {
      database = "authentik";
      user = "authentik";
      ensureDBOwnership = true;
    };

    # 5. Reverse Proxy & Monitoring via Service Contract
    my.contracts.provides.authentik = {
      endpoints.web = {
        port = listenHttpPort;
        protocol = "tcp";
        scope = "public";
        auth = "none";
        subdomain = "auth";
        publicExempt = "identity provider - it cannot sit behind its own forward-auth";
        monitoring = {
          scrape.enable = true;
          scrape.port = 9300;
        };
      };
    };

    # 6. Secrets (Dynamic OIDC Secret Registration - Open-Closed Principle)
    sops.secrets = lib.mkMerge [
      {
        "services/authentik/core_env" = {
          owner = "authentik";
        };
      }
      # Per-outpost LDAP tokens are declared on the server as well so the worker can
      # read them through !File when applying the outpost blueprint.
      (lib.listToAttrs (
        map (o: {
          name = o.tokenSecretName;
          value = {
            owner = "authentik";
          };
        }) blueprints.ldapOutposts
      ))
      (lib.listToAttrs (
        map (ep: {
          name = ep.oidc.secretPath;
          value = { };
        }) (lib.filter (ep: ep.oidc.secretPath != null) (builtins.attrValues blueprints.oidcEndpoints))
      ))
      # The consumers' app passwords are read by the worker at apply time (the token's `key` comes
      # from that file), so they are declared here as well - the same inversion as the outpost tokens.
      (lib.listToAttrs (
        map (name: {
          name = blueprints.ldapConsumerSecretPath name blueprints.ldapEndpoints.${name};
          value = {
            owner = "authentik";
          };
        }) blueprints.sortedLdapEndpointNames
      ))
    ];

    sops.templates."authentik_secrets.env" = {
      owner = "authentik";
      content = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: ep:
          let
            safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
            envVar =
              if ep.oidc.clientSecretEnv != null then
                ep.oidc.clientSecretEnv
              else
                "AUTHENTIK_OIDC_${lib.toUpper safeId}_SECRET";
          in
          "${envVar}=${config.sops.placeholder.${ep.oidc.secretPath}}"
        ) (lib.filterAttrs (_: ep: ep.oidc.secretPath != null) blueprints.oidcEndpoints)
      );
    };
  };
}
