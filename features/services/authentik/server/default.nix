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

  # What the feature depends on, checked after every apply. A successful apply is not the same as a world
  # that matches the declaration: the object permission that lets a consumer read the directory lives in the
  # database rather than in a blueprint, so a fresh install would come up looking healthy while Jellyfin could
  # not search. These are the invariants the design rests on, and a deploy that breaks one must fail.
  blueprintExpectations = {
    # The LDAP application carries no binding, which is what makes it open to every user
    # (AppAccessWithoutBindings, default True); a single binding denies everyone it does not name.
    applicationsWithoutBindings = [ "ldap" ];
    # The flow the outpost executes runs before any account is authenticated, so a binding cannot match.
    flowsWithoutBindings = [ "ldap-authentication-flow" ];
    # The shape of that flow: identification (which carries the password stage), password, and user login.
    flowStageBindings = {
      ldap-authentication-flow = 3;
    };
    # Every consumer's service account must be able to read the whole directory, or the service it serves
    # cannot find its users at all.
    searchFullDirectoryAccounts = map consumerAccountName sortedLdapEndpointNames;
  };

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

    EXPECTED = ${builtins.toJSON blueprintExpectations}

    instances = list(BlueprintInstance.objects.filter(enabled=True))
    if not instances:
        print("no enabled blueprint instances")
        sys.exit(0)

    before = {i.name: i.last_applied for i in instances}
    for instance in instances:
        apply_blueprint.send_with_options(args=(instance.pk,), rel_obj=instance)

    deadline = time.monotonic() + ${toString blueprintsApplyTimeoutSeconds}
    waiting = []
    while True:
        time.sleep(3)
        waiting = []
        for instance in instances:
            instance.refresh_from_db()
            if instance.status == "error":
                print(f"FAILED apply: {instance.name} -> status={instance.status}")
                sys.exit(1)
            previous = before[instance.name]
            if not (
                instance.last_applied is not None
                and instance.status == "successful"
                and (previous is None or instance.last_applied > previous)
            ):
                waiting.append(instance.name)
        if not waiting:
            break
        if time.monotonic() > deadline:
            print("timeout waiting for: " + ", ".join(sorted(waiting)))
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
  directory = config.my.directory.ldap;

  # One rule for the name of every consumer's service account, taken from the directory contract so
  # that a consumer on another host composes exactly the same DN without reading anything of ours.
  consumerAccountName = name: "${config.my.directory.ldap.consumerAccountPrefix}${name}";
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
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  # Flatten all endpoint contracts across all hosts in the cluster
  allClusterEndpointsList = lib.concatMap (
    hostName:
    let
      hostConfig = flakeConfigurations.${hostName}.config;
      provides = hostConfig.my.contracts.provides or { };
    in
    lib.concatLists (
      lib.mapAttrsToList (
        svcName: contract:
        lib.mapAttrsToList (epName: ep: {
          inherit hostName ep;
          name = if epName == "default" || epName == "web" then svcName else "${svcName}-${epName}";
        }) contract.endpoints
      ) provides
    )
  ) (builtins.attrNames flakeConfigurations);

  # Filter forward-auth and OIDC endpoints
  rawAuthEndpointsList = lib.filter (
    item:
    (item.ep.scope == "public" || item.ep.scope == "internal")
    && item.ep.auth == "authentik"
    && item.ep.canonicalDomain != null
  ) allClusterEndpointsList;

  rawOidcEndpointsList = lib.filter (
    item:
    (item.ep.auth == "oidc" || item.ep.oidc.enable)
    && (item.ep.canonicalDomain != null || item.ep.oidc.redirectUris != [ ])
  ) allClusterEndpointsList;

  # LDAP consumers: endpoints that authenticate their users against the directory. For a `web`/
  # `default` endpoint the name is the service name, so `jellyfin` is the whole identity of that
  # consumer - which is also what its secret path and its account name derive from.
  rawLdapEndpointsList = lib.filter (item: item.ep.ldap.enable) allClusterEndpointsList;

  # A consumer without a stated audience has no policy. The contract gives `accessGroups` no default
  # for the same reason; this makes it enforceable rather than a convention.
  ldapPolicyCheck =
    let
      unstated = map (item: item.name) (
        lib.filter (item: item.ep.ldap.accessGroups == [ ]) rawLdapEndpointsList
      );
    in
    if unstated != [ ] then
      throw "Authentik LDAP compiler error: ${lib.concatStringsSep ", " unstated} enables directory authentication without naming accessGroups - a service without a stated audience has no access policy"
    else
      true;

  # The app password lives in SOPS like every other credential; the path is derived so a service only
  # has to say that it wants LDAP, not where its secret lives.
  ldapConsumerSecretPath =
    name: ep:
    if ep.ldap.secretPath != null then
      ep.ldap.secretPath
    else
      "services/authentik/consumers/${name}-ldap-password";

  ldapEndpoints =
    assert ldapPolicyCheck;
    builtins.listToAttrs (
      map (item: {
        inherit (item) name;
        value = item.ep;
      }) rawLdapEndpointsList
    );

  sortedLdapEndpointNames = lib.sort (a: b: a < b) (builtins.attrNames ldapEndpoints);

  # Collision Guard: Assert that no two hosts declare the same OIDC endpoint name
  duplicateOidcCheck =
    let
      names = map (item: item.name) rawOidcEndpointsList;
      duplicates = lib.filter (name: (lib.count (n: n == name) names) > 1) (lib.unique names);
    in
    if duplicates != [ ] then
      throw "Authentik OIDC compiler error: Duplicate OIDC endpoint name(s) across cluster: ${lib.concatStringsSep ", " duplicates}"
    else
      true;

  oidcEndpoints =
    assert duplicateOidcCheck;
    builtins.listToAttrs (
      map (item: {
        inherit (item) name;
        value = item.ep;
      }) rawOidcEndpointsList
    );

  authEndpoints = builtins.listToAttrs (
    map (item: {
      inherit (item) name;
      value = item.ep;
    }) rawAuthEndpointsList
  );

  sortedEndpointNames = lib.sort (a: b: a < b) (builtins.attrNames authEndpoints);
  sortedOidcEndpointNames = lib.sort (a: b: a < b) (builtins.attrNames oidcEndpoints);

  # Blueprints must be *.yaml: authentik's discovery and the blueprint migration only scan for that
  # extension, while everything else about the encoding lives in the constructors.
  toBlueprintYaml =
    name: blueprint:
    let
      serialized = pkgs.writeText "${name}.json" (builtins.toJSON blueprint);
    in
    pkgs.runCommandLocal "${name}.yaml" { } ''
      # The schema line is what editors and any JSON-Schema checker key on; authentik itself ignores it.
      # Field-level validation still happens where it can: in the apply, which is part of the deploy, so a
      # wrong field name fails a deployment rather than producing a blueprint that never applies.
      {
        echo '# yaml-language-server: $schema=https://goauthentik.io/blueprints/schema.json'
        sed 's/"@@YAML_TAG@@\([^"]*\)"/\1/g' ${serialized}
      } > "$out"
    '';

  # authentik does not guarantee any apply order across blueprints (docs:
  # "discovery and evaluation is not guaranteed to follow any specific order").
  # Our generated application/outpost blueprints reference objects owned by
  # upstream default blueprints and by the RBAC blueprint, so the dependency is
  # declared explicitly with the `metaapplyblueprint` meta model instead of
  # relying on filesystem/discovery order.
  metaApply = blueprintLib.metaApply;

  providerFlowDependencies = [
    (metaApply "default/flow-default-provider-authorization-implicit-consent.yaml")
    (metaApply "default/flow-default-provider-invalidation.yaml")
  ];

  ldapDependencies = providerFlowDependencies ++ [
    (metaApply "01-rbac/users-and-groups.yaml")
  ];

  # Declarative model-driven blueprint compiling all auth endpoints into Authentik ProxyProviders and Applications
  # Forward-auth endpoints are served by the embedded outpost that ships with the
  # authentik server. It authenticates with the core secret key (no managed token),
  # so every host's Caddy can forward auth to the same server without per-host
  # proxy outposts.
  proxyBlueprint = blueprintLib.blueprint {
    name = "vyrx-apps-proxy";
    entries =
      providerFlowDependencies
      ++ (lib.concatMap (
        name:
        let
          ep = authEndpoints.${name};
          displayName = if ep.displayName != null then ep.displayName else name;
          group = if ep.group != null then ep.group else "Services";
          safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
        in
        [
          (blueprintLib.proxyProvider {
            id = "provider_proxy_${safeId}";
            name = "Provider for ${displayName}";
            mode = "forward_single";
            externalHost = "https://${ep.canonicalDomain}";
            authorizationFlow = blueprintLib.refs.bySlug blueprintLib.models.flow "default-provider-authorization-implicit-consent";
            invalidationFlow = blueprintLib.refs.bySlug blueprintLib.models.flow "default-provider-invalidation-flow";
          })
          (blueprintLib.application {
            slug = name;
            name = displayName;
            provider = blueprintLib.refs.sameBlueprint "provider_proxy_${safeId}";
            group = group;
            metaLaunchUrl = "https://${ep.canonicalDomain}";
            openInNewTab = true;
          })
        ]
      ) sortedEndpointNames)
      ++ [
        # The outpost embedded in the server itself. It authenticates with the core secret key, so it has no
        # type and no service connection - hence the plain entry rather than the builder, which sets both.
        (blueprintLib.entry {
          id = "embedded_outpost";
          model = blueprintLib.models.outpost;
          identifiers.name = "authentik Embedded Outpost";
          attrs = {
            providers = map (
              name:
              blueprintLib.refs.sameBlueprint "provider_proxy_${builtins.replaceStrings [ "-" ] [ "_" ] name}"
            ) sortedEndpointNames;
            config = {
              authentik_host = "https://${config.my.contracts.provides.authentik.endpoints.web.canonicalDomain}";
              authentik_host_browser = "https://${config.my.contracts.provides.authentik.endpoints.web.canonicalDomain}";
              authentik_host_insecure = false;
            };
          };
        })
      ];
  };

  # Declarative model-driven blueprint compiling all OIDC endpoints into Authentik OAuth2Providers and Applications
  oidcBlueprint = blueprintLib.blueprint {
    name = "vyrx-apps-oidc";
    entries =
      providerFlowDependencies
      ++ lib.concatMap (
        name:
        let
          ep = oidcEndpoints.${name};
          displayName = if ep.displayName != null then ep.displayName else name;
          group = if ep.group != null then ep.group else "Applications";
          safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
          secretAttr =
            if ep.oidc.clientSecretEnv != null then
              blueprintLib.refs.env ep.oidc.clientSecretEnv
            else if ep.oidc.clientSecret != null then
              ep.oidc.clientSecret
            else
              blueprintLib.refs.env "AUTHENTIK_OIDC_${lib.toUpper safeId}_SECRET";
          launchUrl =
            if ep.publicUrl != null then
              ep.publicUrl
            else if ep.canonicalDomain != null then
              "https://${ep.canonicalDomain}"
            else
              null;
        in
        [
          (blueprintLib.oauth2Provider {
            id = "provider_${safeId}";
            name = "Provider for ${displayName}";
            clientId = ep.oidc.clientId;
            clientSecret = secretAttr;
            authorizationFlow = blueprintLib.refs.bySlug blueprintLib.models.flow "default-provider-authorization-implicit-consent";
            invalidationFlow = blueprintLib.refs.bySlug blueprintLib.models.flow "default-provider-invalidation-flow";
            redirectUris = map (uri: {
              matching_mode = "strict";
              url = uri;
            }) ep.oidc.redirectUris;
            subMode = ep.oidc.subMode;
            includeClaimsInIdToken = ep.oidc.includeClaimsInIdToken;
          })
          (blueprintLib.application {
            slug = name;
            name = displayName;
            provider = blueprintLib.refs.sameBlueprint "provider_${safeId}";
            group = group;
            metaLaunchUrl = launchUrl;
            openInNewTab = true;
          })
        ]
      ) sortedOidcEndpointNames;
  };

  generatedProxyBlueprint = toBlueprintYaml "proxy-apps-generated" proxyBlueprint;
  generatedOidcBlueprint = toBlueprintYaml "oidc-apps-generated" oidcBlueprint;

  # LDAP outposts are managed per host. An outpost resolves exactly one outpost from
  # its token (first visible entry), so tokens must never be shared between hosts.
  # Each outpost therefore gets its own service account and token, read at apply
  # time via !File from the host's SOPS secret, which is additionally declared on
  # this server so the file exists for the worker.
  ldapOutposts =
    map
      (
        hostName:
        let
          ldapCfg = flakeConfigurations.${hostName}.config.my.features.services.authentik.outpost.ldap;
        in
        {
          inherit hostName;
          safeHost = builtins.replaceStrings [ "-" ] [ "_" ] hostName;
          inherit (ldapCfg)
            outpostName
            tokenSecretName
            coreAddress
            ;
        }
      )
      (
        lib.filter (
          hostName:
          (flakeConfigurations.${hostName}.config.my.features.services.authentik.outpost.ldap.enable or false)
        ) (builtins.attrNames flakeConfigurations)
      );

  ldapProviderId = "provider_ldap_main";

  ldapOutpostBlueprint = blueprintLib.blueprint {
    name = "vyrx-outposts-ldap";
    entries =
      # The LDAP outpost blueprint depends on the default provider flows and on
      # the RBAC groups, so those are applied first via meta models.
      ldapDependencies
      # Service account + role per host first: the role grants the global read
      # permissions an outpost needs for users/groups/events, while the
      # object-level permissions (provider, outpost) are attached below.
      ++ lib.concatMap (o: [
        (blueprintLib.role {
          id = "role_ldap_${o.safeHost}";
          name = "Outpost LDAP ${o.hostName}";
          permissions = [
            "authentik_core.view_user"
            "authentik_core.view_group"
            "authentik_events.add_event"
          ];
        })
        (blueprintLib.serviceAccount {
          id = "sa_ldap_${o.safeHost}";
          username = "ak-outpost-${o.hostName}-ldap";
          name = "Service Account LDAP Outpost ${o.hostName}";
          roles = [ (blueprintLib.refs.sameBlueprint "role_ldap_${o.safeHost}") ];
        })
      ]) ldapOutposts
      ++ [
        # The bind flow. Documented cause of `Invalid credentials (49)` for a service account: the
        # `default-authentication-flow` validates MFA, and a bind account has no authenticator. The
        # authentik how-to prescribes a dedicated flow whose password stage carries the app-password
        # backend.
        #
        # No policy binding on this flow, deliberately: the outpost executes it before any account is
        # authenticated, so a binding naming the service account cannot match and the flow answers
        # "Flow does not apply to current user". An unbound flow applies to everyone, which is what a
        # bind needs; who may use a service is decided afterwards, in the consumer's own memberOf filter.
        (blueprintLib.flow {
          id = "flow_ldap_auth";
          slug = "ldap-authentication-flow";
          name = "LDAP authentication flow";
          title = "LDAP";
          designation = "authentication";
        })
        (blueprintLib.passwordStage {
          id = "stage_ldap_password";
          name = "ldap-authentication-password-stage";
          # `InbuiltBackend` accepts a real password, `TokenBackend` an app password; a service account
          # has no usable password, so the second is what makes the bind possible at all.
          backends = [
            "authentik.core.auth.InbuiltBackend"
            "authentik.core.auth.TokenBackend"
          ];
        })
        (blueprintLib.identificationStage {
          id = "stage_ldap_identification";
          name = "ldap-identification-stage";
          userFields = [
            "username"
            "email"
          ];
          passwordStage = blueprintLib.refs.sameBlueprint "stage_ldap_password";
        })
        (blueprintLib.userLoginStage {
          id = "stage_ldap_login";
          name = "ldap-authentication-login-stage";
        })
        (blueprintLib.flowStageBinding {
          order = 10;
          target = blueprintLib.refs.sameBlueprint "flow_ldap_auth";
          stage = blueprintLib.refs.sameBlueprint "stage_ldap_identification";
        })
        (blueprintLib.flowStageBinding {
          order = 30;
          target = blueprintLib.refs.sameBlueprint "flow_ldap_auth";
          stage = blueprintLib.refs.sameBlueprint "stage_ldap_password";
        })
        (blueprintLib.flowStageBinding {
          order = 40;
          target = blueprintLib.refs.sameBlueprint "flow_ldap_auth";
          stage = blueprintLib.refs.sameBlueprint "stage_ldap_login";
        })
        (blueprintLib.ldapProvider {
          id = ldapProviderId;
          name = "VYRX LDAP Provider";
          baseDn = directory.baseDn;
          # Binds go through the dedicated flow above; the default one validates MFA, which a service
          # account cannot satisfy. Which of these two fields the outpost consumes is counter-intuitive
          # and documented in the library: it reads `authorization_flow` as its bind flow.
          authenticationFlow = blueprintLib.refs.sameBlueprint "flow_ldap_auth";
          authorizationFlow = blueprintLib.refs.bySlug blueprintLib.models.flow "ldap-authentication-flow";
          invalidationFlow = blueprintLib.refs.bySlug blueprintLib.models.flow "default-provider-invalidation-flow";
          permissions =
            # Object permissions on the provider, one per role that needs them. The consumer role lives in
            # another blueprint, so it is resolved with !Find: a `!KeyOf` across blueprint boundaries
            # produces an entry that is skipped without an error, which is what earlier attempts here
            # suffered from.
            map (o: {
              permission = "authentik_providers_ldap.view_ldapprovider";
              role = blueprintLib.refs.sameBlueprint "role_ldap_${o.safeHost}";
            }) ldapOutposts
            ++ map (name: {
              permission = "authentik_providers_ldap.search_full_directory";
              role = blueprintLib.refs.byName blueprintLib.models.role "LDAP consumer ${name}";
            }) sortedLdapEndpointNames;
        })
        # The LDAP outpost config endpoint only exposes providers that are bound to an application, so the
        # provider is linked here explicitly.
        (blueprintLib.application {
          slug = "ldap";
          name = "LDAP Directory";
          provider = blueprintLib.refs.sameBlueprint ldapProviderId;
        })
      ]
      ++ lib.concatMap (o: [
        (blueprintLib.token {
          identifier = "outpost-${o.hostName}-ldap-token";
          intent = "api";
          user = blueprintLib.refs.sameBlueprint "sa_ldap_${o.safeHost}";
          key = blueprintLib.refs.file config.sops.secrets.${o.tokenSecretName}.path;
        })
        (blueprintLib.outpost {
          id = "outpost_ldap_${o.safeHost}";
          name = o.outpostName;
          type = "ldap";
          providers = [ (blueprintLib.refs.sameBlueprint ldapProviderId) ];
          config = {
            authentik_host = o.coreAddress;
            authentik_host_insecure = true;
          };
          permissions = [
            {
              permission = "authentik_outposts.view_outpost";
              role = blueprintLib.refs.sameBlueprint "role_ldap_${o.safeHost}";
            }
          ];
        })
      ]) ldapOutposts;
  };

  generatedLdapOutpostBlueprint = toBlueprintYaml "ldap-outposts-generated" ldapOutpostBlueprint;

  # One search account per consumer, which is the shape the Authentik documentation prescribes
  # ("Example: LDAP search account"): a service account, an **app password** - not an API token, which
  # authenticates against the HTTP API only and is rejected by an LDAP bind (measured: `Invalid
  # credentials (49)` with the outpost's API token against a DN that exists) - a role, and the
  # "Search full LDAP directory" object permission on the provider, added above.
  ldapConsumerBlueprint = blueprintLib.blueprint {
    name = "vyrx-ldap-consumers";
    entries =
      # Tombstones. A blueprint declares the entries it contains, so removal is expressed as an entry
      # with `state: absent`: it deletes the object when it exists and does nothing when it does not.
      # The upstream structure documentation lists present, created, must_created and absent; an earlier
      # revision of this feature declared these three objects while the authorization question was being
      # traced, and the file no longer wants them.
      #
      # Deleting a flow cascades to its stage bindings, which is why no binding is listed here.
      [
        (blueprintLib.absent {
          model = blueprintLib.models.flow;
          identifiers.slug = "ldap-authorization-flow";
        })
        (blueprintLib.absent {
          model = blueprintLib.models.consentStage;
          identifiers.name = "Authorize LDAP consumer";
        })
        (blueprintLib.absent {
          model = blueprintLib.models.userLoginStage;
          identifiers.name = "Authorize LDAP consumer";
        })
      ]
      ++ lib.concatMap (
        name:
        let
          ep = ldapEndpoints.${name};
          safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
        in
        [
          (blueprintLib.role {
            id = "role_ldap_consumer_${safeId}";
            name = "LDAP consumer ${name}";
          })
          (blueprintLib.serviceAccount {
            id = "sa_ldap_consumer_${safeId}";
            username = consumerAccountName name;
            name = "LDAP search account for ${name}";
            roles = [ (blueprintLib.refs.sameBlueprint "role_ldap_consumer_${safeId}") ];
          })
          # Deliberately no binding on the LDAP application and none on the flow the outpost executes.
          #
          # The outpost checks per user whether that user may use the application
          # (providers/ldap/api.py runs PolicyEngine(application, request.user); bind.go answers
          # LDAPResultInsufficientAccessRights when it does not pass). With a single binding naming the
          # service account, every human failed that check with 50 while the service account passed -
          # measured with the same account: 49 with a wrong password, 50 with the right one.
          #
          # An application without any binding is accessible to every user: the flag behind it is
          # AppAccessWithoutBindings, key `core_default_app_access`, default True. The directory therefore
          # stays open to bind, and who may use a service is decided where it belongs - in the consumer's
          # own memberOf filter, projected from its endpoint contract. The same reasoning holds for the
          # bind flow, which the outpost runs before any account is authenticated.
          (blueprintLib.token {
            identifier = "ldap-consumer-${name}-password";
            intent = "app_password";
            user = blueprintLib.refs.sameBlueprint "sa_ldap_consumer_${safeId}";
            key = blueprintLib.refs.file config.sops.secrets.${ldapConsumerSecretPath name ep}.path;
          })
        ]
      ) sortedLdapEndpointNames;
  };

  generatedLdapConsumerBlueprint = toBlueprintYaml "ldap-consumers-generated" ldapConsumerBlueprint;

  # Merged blueprints directory containing upstream base blueprints, custom blueprints and generated applications
  effectiveBlueprintsDir = pkgs.runCommandLocal "authentik-blueprints" { } ''
    mkdir -p "$out"
    # 1. Inherit upstream system and default blueprints (required for initial flows and setup)
    cp -r ${authentikPackage.src}/blueprints/* "$out/"
    chmod -R u+w "$out"

    # 2. Overlay VYRX custom blueprints
    cp -r ${./blueprints}/* "$out/"

    # 3. Inject compiled application blueprints
    mkdir -p "$out/03-apps"
    cp ${generatedProxyBlueprint} "$out/03-apps/proxy-apps-generated.yaml"
    cp ${generatedOidcBlueprint} "$out/03-apps/oidc-apps-generated.yaml"
    cp ${generatedLdapOutpostBlueprint} "$out/03-apps/ldap-outposts-generated.yaml"
    cp ${generatedLdapConsumerBlueprint} "$out/03-apps/ldap-consumers-generated.yaml"
  '';

  # Apply path: blueprint changes ship inside the system closure. `nod switch
  # cld-edge-01` installs the new effectiveBlueprintsDir; the service
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
            (flakeConfigurations.${hostName}.config.my.features.services.authentik.server.enable or false)
          ) (builtins.attrNames flakeConfigurations);
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
      default = effectiveBlueprintsDir;
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
        }) ldapOutposts
      ))
      (lib.listToAttrs (
        map (ep: {
          name = ep.oidc.secretPath;
          value = { };
        }) (lib.filter (ep: ep.oidc.secretPath != null) (builtins.attrValues oidcEndpoints))
      ))
      # The consumers' app passwords are read by the worker at apply time (the token's `key` comes
      # from that file), so they are declared here as well - the same inversion as the outpost tokens.
      (lib.listToAttrs (
        map (name: {
          name = ldapConsumerSecretPath name ldapEndpoints.${name};
          value = {
            owner = "authentik";
          };
        }) sortedLdapEndpointNames
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
        ) (lib.filterAttrs (_: ep: ep.oidc.secretPath != null) oidcEndpoints)
      );
    };
  };
}
