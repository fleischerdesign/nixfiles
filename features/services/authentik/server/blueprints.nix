# features/services/authentik/server/blueprints.nix
# The generated blueprints: endpoint discovery, the compiler checks, the four blueprint documents and the
# directory they are assembled into.
#
# They live apart from the server module because they have a different owner and a different lifetime:
# this file knows authentik's object model and the contracts of the fleet, while the server module knows
# how authentik is run here - units, environment, secrets, and the apply that turns these files into
# objects. The split is mechanical and verified: the assembled directory is byte-compared before and after.
{
  config,
  lib,
  pkgs,
  blueprintLib,
}:
let
  authentikPackage = pkgs.authentik;
  directory = config.my.directory.ldap;
  consumerAccountName = name: "${config.my.directory.ldap.consumerAccountPrefix}${name}";

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

  # The LDAP outpost blueprint depends on the default provider flows, on the RBAC groups, and on the consumer
  # blueprint: it carries an object permission for each consumer's role, and those roles are created by
  # `vyrx-ldap-consumers`. Declared as a dependency rather than hoped for, because authentik guarantees no
  # apply order across files.
  ldapDependencies = providerFlowDependencies ++ [
    (metaApply "01-rbac/users-and-groups.yaml")
    (blueprintLib.metaApplyInstance "vyrx-ldap-consumers")
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

in
{
  # The invariants the apply checks after every run.
  expectations = blueprintExpectations;

  # The blueprint directory that ships inside the system closure.
  dir = effectiveBlueprintsDir;

  # What the server module needs for its own concerns. It declares the SOPS secrets for the consumer
  # accounts and for the outpost tokens, so it has to know which endpoints and hosts exist and where those
  # secrets live - the facts, not the blueprints.
  inherit
    flakeConfigurations
    ldapOutposts
    ldapEndpoints
    sortedLdapEndpointNames
    oidcEndpoints
    ldapConsumerSecretPath
    ;
}
