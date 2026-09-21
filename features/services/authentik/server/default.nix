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

  # The core as this host reaches it: the LAN address while both sides are at home, otherwise the overlay
  # address (lib/addresses.nix).
  addresses = import ../../../../lib/addresses.nix { inherit lib; };

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

  # Apply path: queue the task and wait for the effect, then check the invariants above. Only the blueprints
  # this repository owns are sent - the ownership label, not `enabled`, decides. Applying authentik's own
  # defaults would silently revert an administrator's edit to their objects at every deploy (see E1). It
  # asserts on `last_applied` rather than on `status` alone: status describes the last attempt, so a failed
  # apply leaves the previous value behind and a blueprint can read `successful` while the object it declares
  # does not exist.
  blueprintsApplyScript = pkgs.writeText "authentik-apply-blueprints.py" ''
    import sys
    import time
    from pathlib import Path

    from yaml import YAMLError, load

    from django.apps import apps

    from authentik.blueprints.models import BlueprintInstance
    from authentik.blueprints.v1.common import BlueprintEntryDesiredState, BlueprintLoader, YAMLTag
    from authentik.blueprints.v1.importer import Importer
    from authentik.blueprints.v1.tasks import apply_blueprint
    from authentik.core.models import Token, User
    from authentik.lib.config import CONFIG
    from authentik.providers.ldap.models import LDAPProvider

    EXPECTED = ${builtins.toJSON blueprints.expectations}
    OWNER_LABEL = ("${blueprintLib.ownerLabelName}", "${blueprintLib.ownerLabelValue}")
    root = Path(CONFIG.get("blueprints_dir"))
    deadline = time.monotonic() + ${toString blueprintsApplyTimeoutSeconds}

    ${ownershipPython}

    ${relationsPython}

    paths = owned_paths()
    if not paths:
        print("FAILED: no owned blueprints in " + str(CONFIG.get("blueprints_dir")))
        sys.exit(1)

    # The worker's discovery creates the instance rows, asynchronously and not necessarily before this unit
    # starts on a fresh database. Wait for every owned file to be instantiated before applying any of them.
    while True:
        instances = list(BlueprintInstance.objects.filter(enabled=True, path__in=paths))
        missing = sorted(set(paths) - {instance.path for instance in instances})
        if not missing:
            break
        if time.monotonic() > deadline:
            print("FAILED, discovery did not instantiate: " + ", ".join(missing))
            sys.exit(1)
        time.sleep(3)

    before = {i.name: i.last_applied for i in instances}

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

    # Derived invariants. The existential level parses every owned blueprint with the importer - the same
    # source the apply uses - and queries the database for each declared object, so a missing object fails
    # the deploy instead of hiding behind a `successful` status (the failure mode of §6.2). Entry types
    # whose identifiers contain a YAML tag (stage and policy bindings) are covered by the cardinal checks
    # below. A tombstone must resolve to nothing: that is the rename discipline of §11.3, enforced.
    for path in paths:
        blueprint = Importer.from_string((root / path).read_text(encoding="utf-8"), {}).blueprint
        for entry in blueprint.iter_entries():
            model_name = entry.get_model(blueprint)
            if model_name == "authentik_blueprints.metaapplyblueprint":
                continue
            identifiers = entry.identifiers or {}
            if any(isinstance(value, YAMLTag) for value in identifiers.values()):
                continue
            model = apps.get_model(*model_name.split("."))
            exists = model.objects.filter(**identifiers).exists()
            state = entry.get_state(blueprint)
            if state == BlueprintEntryDesiredState.ABSENT:
                expect(f"tombstone {model_name} {identifiers} is gone", not exists)
            else:
                expect(f"{model_name} {identifiers} resolves to an object", exists)

    for identifier in EXPECTED["sopsBackedTokens"]:
        token = Token.objects.filter(identifier=identifier).first()
        expect(f"token {identifier} exists", token is not None)
        if token is not None:
            expect(f"token {identifier} is unmanaged (managed={token.managed!r})", token.managed is None)
            expect(f"token {identifier} does not expire (expiring={token.expiring!r})", token.expiring is False)

    # Relation ownership: the declared relation sets are derived from the blueprints themselves (see
    # relation_diffs), so a relation this repository does not declare - like the 2026-09-20 orphaned
    # bindings on the shared authorization flow - fails the deploy instead of denying every login.
    failures.extend(relation_diffs(paths))

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

  # Drift report: report only, never correct. The apply only runs when the deployment changed, so a
  # change made in the interface is invisible until the next deploy - exactly the window in which the
  # ownership rule needs a voice. It compares the declared scalar fields against the objects and lists
  # the recent interface events, and it writes nothing.
  driftReportScript = pkgs.writeText "authentik-drift-report.py" ''
    import sys
    from pathlib import Path

    from django.apps import apps
    from yaml import YAMLError, load

    from authentik.blueprints.v1.common import BlueprintEntryDesiredState, BlueprintLoader, YAMLTag
    from authentik.blueprints.v1.importer import Importer
    from authentik.events.models import Event
    from authentik.lib.config import CONFIG

    OWNER_LABEL = ("${blueprintLib.ownerLabelName}", "${blueprintLib.ownerLabelValue}")
    root = Path(CONFIG.get("blueprints_dir"))

    ${ownershipPython}

    ${relationsPython}

    def scalar(value):
        """Only plain values are compared. References, files, lists and FKs are not drift."""
        return isinstance(value, (str, bool, int)) and not isinstance(value, YAMLTag)

    findings = []
    paths = owned_paths()
    for rel in paths:
        blueprint = Importer.from_string((root / rel).read_text(encoding="utf-8"), {}).blueprint
        for entry in blueprint.iter_entries():
            model_name = entry.get_model(blueprint)
            if model_name == "authentik_blueprints.metaapplyblueprint":
                continue
            identifiers = entry.identifiers or {}
            if any(isinstance(value, YAMLTag) for value in identifiers.values()):
                continue
            model = apps.get_model(*model_name.split("."))
            instance = model.objects.filter(**identifiers).first()
            state = entry.get_state(blueprint)
            if instance is None:
                if state != BlueprintEntryDesiredState.ABSENT:
                    findings.append(f"MISSING {model_name} {identifiers}: declared but not in the database")
                continue
            if state == BlueprintEntryDesiredState.ABSENT:
                findings.append(f"STALE {model_name} {identifiers}: tombstoned but still present")
                continue
            for field, declared in (entry.attrs or {}).items():
                if not scalar(declared):
                    continue
                current = getattr(instance, field, None)
                if scalar(current) and current != declared:
                    findings.append(
                        f"RESET {model_name} {identifiers} field {field}: "
                        f"database {current!r}, declared {declared!r}"
                    )

    # The same derived relation inventory the apply enforces, reported instead of corrected.
    findings.extend(relation_diffs(paths))

    print(f"drift report: {len(findings)} finding(s)")
    for finding in findings:
        print("DRIFT " + finding)

    recent = list(
        Event.objects.filter(
            action__in=["model_updated", "model_created", "model_deleted"],
        ).order_by("-created")[:50]
    )
    print(f"interface events: {len(recent)} recent")
    for event in recent:
        user = (event.user or {}).get("username", "<system>")
        print(f"EVENT {event.created.isoformat()} {event.action} user={user} {event.context}")
    sys.exit(0)
  '';

  # The environment every authentik process shares. Defined once so the four units cannot drift apart;
  # `authentikBlueprintEnvironment` holds what a process needs while it applies or bootstraps.
  authentikEnvironmentFiles = [
    config.sops.secrets."services/authentik/core_env".path
    config.sops.templates."authentik_secrets.env".path
  ];

  authentikDatabaseEnvironment = [
    "AUTHENTIK_REDIS__HOST=127.0.0.1"
    "AUTHENTIK_REDIS__PORT=6379"
    "AUTHENTIK_POSTGRESQL__HOST=/run/postgresql"
    "AUTHENTIK_POSTGRESQL__NAME=authentik"
    "AUTHENTIK_POSTGRESQL__USER=authentik"
  ];

  authentikBlueprintEnvironment = [
    "AUTHENTIK_BOOTSTRAP_EMAIL=${cfg.adminEmail}"
    "AUTHENTIK_RECOVERY_FROM_ADDRESS=noreply@${config.my.topology.domain}"
    "AUTHENTIK_BLUEPRINTS_DIR=${cfg.blueprintsDir}"
  ];

  # The ownership reader, defined once and interpolated into both scripts, so the apply and the drift
  # report can never disagree about which blueprints this repository owns.
  ownershipPython = ''
    def owned_paths():
        """The paths of the blueprints this repository owns, read from the deployed files themselves.

        The label is the ownership marker. Reading it from the directory rather than from
        `instance.metadata` closes a chicken-and-egg on a fresh database: metadata is only written once an
        instance is applied, so selecting on it would apply nothing exactly while the world is being built.
        The files are the declaration the deploy just shipped, so they are the authority on who we are.
        """
        owned = []
        for path in sorted(root.rglob("*.yaml")):
            if any(part.startswith(".") for part in path.parts):
                continue
            with open(path, encoding="utf-8") as handle:
                try:
                    raw = load(handle.read(), BlueprintLoader)
                except YAMLError as exc:
                    print(f"FAILED parse {path}: {exc}")
                    sys.exit(1)
            metadata = (raw or {}).get("metadata") or {}
            if (metadata.get("labels") or {}).get(OWNER_LABEL[0]) == OWNER_LABEL[1]:
                owned.append(str(path.relative_to(root)))
        return owned
  '';

  # Relation ownership: the repository owns the *set* of relations on every object its blueprints
  # declare or reference, and the blueprints are the single source for that set. This derives the
  # expected counts from the same entries that generate the YAML - no hand-written model or slug list -
  # and returns what differs from the database. The apply fails on a non-empty result; the drift report
  # prints it. Only objects our entries touch are asserted, because upstream owns its own bindings.
  relationsPython = ''
    def relation_diffs(paths):
        """Declared-vs-actual relation differences for the owned blueprints; empty means they match."""
        from django.apps import apps

        from authentik.blueprints.v1.common import BlueprintEntryDesiredState, Find, KeyOf
        from authentik.blueprints.v1.importer import Importer
        from authentik.flows.models import Flow, FlowStageBinding
        from authentik.policies.models import PolicyBinding, PolicyBindingModel

        flow_model = "authentik_flows.flow"
        binding_model = "authentik_policies.policybinding"
        stage_binding_model = "authentik_flows.flowstagebinding"

        def tags(value):
            if isinstance(value, (Find, KeyOf)):
                yield value
            elif isinstance(value, dict):
                for inner in value.values():
                    yield from tags(inner)
            elif isinstance(value, list):
                for inner in value:
                    yield from tags(inner)

        def key_of(tag, index):
            if isinstance(tag, KeyOf):
                return index.get(tag.id_from)
            if isinstance(tag, Find) and len(tag.conditions) == 1:
                field, value = tag.conditions[0]
                return (tag.model_name, field, value)
            return None

        def resolve(key):
            if key is None:
                return None
            model, field, value = key
            return apps.get_model(*model.split(".")).objects.filter(**{field: value}).first()

        def label(key):
            return f"{key[0]} {key[1]}={key[2]}"

        diffs = []
        for path in paths:
            blueprint = Importer.from_string((root / path).read_text(encoding="utf-8"), {}).blueprint
            index = {}
            for entry in blueprint.iter_entries():
                identifiers = entry.identifiers or {}
                if entry.id and len(identifiers) == 1:
                    field, value = next(iter(identifiers.items()))
                    index[entry.id] = (entry.get_model(blueprint), field, value)

            # A target is keyed by the foreign key the database actually holds: `pbm_uuid` for a policy
            # binding, `flow_uuid` for a stage binding. A Flow carries both, and a reference through the
            # base model and one through the flow resolve to different pks, so comparing model names or
            # object pks would silently count the wrong thing.
            policy_targets = {}
            stage_targets = {}
            declared_policy = {}
            declared_stage = {}
            for entry in blueprint.iter_entries():
                model = entry.get_model(blueprint)
                identifiers = entry.identifiers or {}
                # A tombstone declares that an object must not exist; it neither declares a relation nor
                # contributes a target to assert on.
                if entry.get_state(blueprint) == BlueprintEntryDesiredState.ABSENT:
                    continue
                # An object we declare: we own its relation sets.
                if len(identifiers) == 1 and not any(isinstance(v, (Find, KeyOf)) for v in identifiers.values()):
                    field, value = next(iter(identifiers.items()))
                    key = (model, field, value)
                    obj = resolve(key)
                    if isinstance(obj, PolicyBindingModel):
                        policy_targets.setdefault(obj.pbm_uuid, label(key))
                    if model == flow_model and obj is not None:
                        stage_targets.setdefault(obj.flow_uuid, label(key))
                # An object we merely reference: we own its policy bindings, not its upstream stage shape.
                for container in (entry.identifiers or {}), (entry.attrs or {}):
                    for value in container.values():
                        for tag in tags(value):
                            key = key_of(tag, index)
                            obj = resolve(key)
                            if isinstance(obj, PolicyBindingModel):
                                policy_targets.setdefault(obj.pbm_uuid, label(key))
                if model == binding_model:
                    obj = resolve(key_of(identifiers.get("target"), index))
                    if isinstance(obj, PolicyBindingModel):
                        declared_policy[obj.pbm_uuid] = declared_policy.get(obj.pbm_uuid, 0) + 1
                elif model == stage_binding_model:
                    obj = resolve(key_of(identifiers.get("target"), index))
                    if isinstance(obj, Flow):
                        declared_stage[obj.flow_uuid] = declared_stage.get(obj.flow_uuid, 0) + 1

            for target, description in sorted(policy_targets.items(), key=lambda item: item[1]):
                expected = declared_policy.get(target, 0)
                found = PolicyBinding.objects.filter(target_id=target).count()
                if found != expected:
                    diffs.append(
                        f"policy bindings on {description}: {found} in the database, {expected} declared"
                    )
            for target, description in sorted(stage_targets.items(), key=lambda item: item[1]):
                expected = declared_stage.get(target, 0)
                found = FlowStageBinding.objects.filter(target_id=target).count()
                if found != expected:
                    diffs.append(
                        f"stage bindings on {description}: {found} in the database, {expected} declared"
                    )
        return diffs
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
          "${
            addresses.serviceAddress {
              topology = config.my.topology;
              consumer = config.my.topology.hosts.${config.networking.hostName} or null;
              peer = config.my.topology.hosts.${serverHost};
            }
          }:${toString listenHttpPort}";
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
        EnvironmentFile = authentikEnvironmentFiles;
        Environment =
          authentikDatabaseEnvironment
          ++ [
            # The embedded proxy outpost and the API share this listener.
            "AUTHENTIK_LISTEN__HTTP=0.0.0.0:${toString listenHttpPort}"
            "AUTHENTIK_LISTEN__METRICS=0.0.0.0:9300"
            "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=${trustedProxyCidrs}"
            "AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true"
            "AUTHENTIK_AVATARS=gravatar"
            "AUTHENTIK_EVENTS__CONTEXT_PROCESSORS__GEOIP=/var/lib/GeoIP/GeoLite2-City.mmdb"
          ]
          # Populate the bootstrap admin on first start. The plaintext break-glass password lives in the
          # core_env secret as `AUTHENTIK_BOOTSTRAP_PASSWORD`; it is only consumed while `akadmin` does
          # not exist yet, so it never resets a password that has already been changed.
          ++ authentikBlueprintEnvironment;
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
        EnvironmentFile = authentikEnvironmentFiles;
        Environment =
          authentikDatabaseEnvironment
          ++ [
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
          ]
          ++ authentikBlueprintEnvironment;
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
        EnvironmentFile = authentikEnvironmentFiles;
        Environment = authentikDatabaseEnvironment ++ authentikBlueprintEnvironment;
        ExecStart = "${lib.getExe authentikPackage} shell";
        StandardInput = "file:${blueprintsApplyScript}";
      };
    };

    # Drift report, report only. It runs when a deploy changes the blueprints (so the report lands next to
    # the apply) and daily (so a change made in the interface is reported even when nobody deploys). It
    # always exits 0: a report that fails would be an alarm, and the intent is to name the drift without
    # changing anything.
    systemd.services.authentik-drift-report = {
      description = "Report drift between the declared blueprints and the database";
      wantedBy = [ "multi-user.target" ];
      # Run after the apply, not beside it: a report that reads the database while the apply is still
      # settling reported the SOPS tokens as missing on 2026-09-20 (a transient false positive).
      after = [
        "authentik-worker.service"
        "authentik-blueprints-apply.service"
      ];
      requires = [
        "authentik-worker.service"
        "authentik-blueprints-apply.service"
      ];
      restartTriggers = [ cfg.blueprintsDir ];
      serviceConfig = {
        Type = "oneshot";
        User = "authentik";
        Group = "authentik";
        WorkingDirectory = "/var/lib/authentik";
        EnvironmentFile = authentikEnvironmentFiles;
        Environment = authentikDatabaseEnvironment ++ [ "AUTHENTIK_BLUEPRINTS_DIR=${cfg.blueprintsDir}" ];
        ExecStart = "${lib.getExe authentikPackage} shell";
        StandardInput = "file:${driftReportScript}";
      };
    };

    systemd.timers.authentik-drift-report = {
      description = "Daily drift report for the declared blueprints";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # The deploy is not finished when the apply unit was started, only when it succeeded. `nod` runs
    # custom probes after activation; this one observes the asynchronous apply unit and asserts its
    # result, so a red apply fails the deploy instead of only the journal.
    nod.healthChecks = {
      timeoutSecs = blueprintsApplyTimeoutSeconds + 120;
      customProbes = [
        {
          name = "authentik-blueprints-applied";
          timeoutSecs = blueprintsApplyTimeoutSeconds + 60;
          command = ''
            while [ "$(systemctl show -p ActiveState --value authentik-blueprints-apply.service)" = "activating" ]; do
              sleep 3
            done
            test "$(systemctl show -p Result --value authentik-blueprints-apply.service)" = success
          '';
        }
      ];
    };

    # 4. Inversion of Control: Declare PostgreSQL requirement
    my.contracts.consumes.authentik.postgresql.main = {
      database = "authentik";
      user = "authentik";
      ensureDBOwnership = true;
    };

    # 5. Reverse Proxy & Monitoring via Service Contract
    my.contracts.provides.authentik = {
      # The server's own listeners. The ingress proxies to `web` on this host, so they are the local
      # network's business and nobody else's - declared local, which is what the exposure inventory reads
      # as "a decision", not as "forgotten".
      # The server's own HTTP and HTTPS faces. The ingress reaches the service through `web` (9055) on this
      # host, so nothing outside talks to these two; authentik listens on them regardless. Declared local,
      # which is what the exposure inventory reads as a decision.
      endpoints.http = {
        port = 9000;
        protocol = "tcp";
        scope = "isolated";
        directAccess = {
          enable = true;
          interface = "local";
          protocol = "tcp";
        };
      };
      endpoints.https = {
        port = 9443;
        protocol = "tcp";
        scope = "isolated";
        directAccess = {
          enable = true;
          interface = "local";
          protocol = "tcp";
        };
      };
      endpoints.metrics = {
        port = 9300;
        protocol = "tcp";
        scope = "isolated";
        directAccess = {
          enable = true;
          interface = "local";
          protocol = "tcp";
        };
      };
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
