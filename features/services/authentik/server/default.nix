{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.authentik.server;
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

  # Authentik blueprint references (!KeyOf, !Find, !Env, ...) are YAML-level tags.
  # Neither builtins.toJSON nor a plain YAML emitter can express them, so tagged
  # values carry a sentinel prefix that is converted into a real YAML tag after
  # serialization. Blueprints must be *.yaml: authentik's discovery and the
  # blueprint migration only scan for *.yaml files.
  yamlTag = value: "@@YAML_TAG@@${value}";

  toBlueprintYaml =
    name: blueprint:
    let
      serialized = pkgs.writeText "${name}.json" (builtins.toJSON blueprint);
    in
    pkgs.runCommandLocal "${name}.yaml" { } ''
      sed 's/"@@YAML_TAG@@\([^"]*\)"/\1/g' ${serialized} > "$out"
    '';

  # authentik does not guarantee any apply order across blueprints (docs:
  # "discovery and evaluation is not guaranteed to follow any specific order").
  # Our generated application/outpost blueprints reference objects owned by
  # upstream default blueprints and by the RBAC blueprint, so the dependency is
  # declared explicitly with the `metaapplyblueprint` meta model instead of
  # relying on filesystem/discovery order.
  metaApply = path: {
    model = "authentik_blueprints.metaapplyblueprint";
    attrs = {
      identifiers = {
        inherit path;
      };
    };
  };

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
  proxyBlueprint = {
    version = 1;
    metadata = {
      name = "vyrx-apps-proxy";
    };
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
          {
            model = "authentik_providers_proxy.proxyprovider";
            id = "provider_proxy_${safeId}";
            identifiers = {
              name = "Provider for ${displayName}";
            };
            attrs = {
              mode = "forward_single";
              external_host = "https://${ep.canonicalDomain}";
              authorization_flow = yamlTag "!Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]";
              invalidation_flow = yamlTag "!Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]";
            };
          }
          {
            model = "authentik_core.application";
            identifiers = {
              slug = name;
            };
            attrs = {
              name = displayName;
              provider = yamlTag "!KeyOf provider_proxy_${safeId}";
              meta_launch_url = "https://${ep.canonicalDomain}";
              inherit group;
              open_in_new_tab = true;
            };
          }
        ]
      ) sortedEndpointNames)
      ++ [
        {
          model = "authentik_outposts.outpost";
          id = "embedded_outpost";
          identifiers = {
            name = "authentik Embedded Outpost";
          };
          attrs = {
            providers = map (
              name:
              let
                safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
              in
              yamlTag "!KeyOf provider_proxy_${safeId}"
            ) sortedEndpointNames;
            config = {
              authentik_host = "https://${config.my.contracts.provides.authentik.endpoints.web.canonicalDomain}";
              authentik_host_browser = "https://${config.my.contracts.provides.authentik.endpoints.web.canonicalDomain}";
              authentik_host_insecure = false;
            };
          };
        }
      ];
  };

  # Declarative model-driven blueprint compiling all OIDC endpoints into Authentik OAuth2Providers and Applications
  oidcBlueprint = {
    version = 1;
    metadata = {
      name = "vyrx-apps-oidc";
    };
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
              yamlTag "!Env ${ep.oidc.clientSecretEnv}"
            else if ep.oidc.clientSecret != null then
              ep.oidc.clientSecret
            else
              yamlTag "!Env AUTHENTIK_OIDC_${lib.toUpper safeId}_SECRET";
          launchUrl =
            if ep.publicUrl != null then
              ep.publicUrl
            else if ep.canonicalDomain != null then
              "https://${ep.canonicalDomain}"
            else
              null;
        in
        [
          {
            model = "authentik_providers_oauth2.oauth2provider";
            id = "provider_${safeId}";
            identifiers = {
              name = "Provider for ${displayName}";
            };
            attrs = {
              client_id = ep.oidc.clientId;
              client_secret = secretAttr;
              authorization_flow = yamlTag "!Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]";
              invalidation_flow = yamlTag "!Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]";
              redirect_uris = map (uri: {
                matching_mode = "strict";
                url = uri;
              }) ep.oidc.redirectUris;
              sub_mode = ep.oidc.subMode;
              include_claims_in_id_token = ep.oidc.includeClaimsInIdToken;
            };
          }
          {
            model = "authentik_core.application";
            identifiers = {
              slug = name;
            };
            attrs = {
              name = displayName;
              provider = yamlTag "!KeyOf provider_${safeId}";
              meta_launch_url = launchUrl;
              inherit group;
              open_in_new_tab = true;
            };
          }
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

  ldapOutpostBlueprint = {
    version = 1;
    metadata = {
      name = "vyrx-outposts-ldap";
    };
    entries =
      # The LDAP outpost blueprint depends on the default provider flows and on
      # the RBAC groups, so those are applied first via meta models.
      ldapDependencies
      # Service account + role per host first: the role grants the global read
      # permissions an outpost needs for users/groups/events, while the
      # object-level permissions (provider, outpost) are attached below.
      ++ lib.concatMap (o: [
        {
          model = "authentik_rbac.role";
          id = "role_ldap_${o.safeHost}";
          identifiers = {
            name = "Outpost LDAP ${o.hostName}";
          };
          attrs = {
            permissions = [
              "authentik_core.view_user"
              "authentik_core.view_group"
              "authentik_events.add_event"
            ];
          };
        }
        {
          model = "authentik_core.user";
          id = "sa_ldap_${o.safeHost}";
          identifiers = {
            username = "ak-outpost-${o.hostName}-ldap";
          };
          attrs = {
            name = "Service Account LDAP Outpost ${o.hostName}";
            type = "service_account";
            roles = [ (yamlTag "!KeyOf role_ldap_${o.safeHost}") ];
          };
        }
      ]) ldapOutposts
      ++ [
        {
          model = "authentik_providers_ldap.ldapprovider";
          id = ldapProviderId;
          identifiers = {
            name = "VYRX LDAP Provider";
          };
          attrs = {
            base_dn = "DC=vyrx,DC=de";
            # No `search_group` and no other access restriction here, for two reasons, both
            # measured: the field does not exist on this version's LDAP provider
            # (authentik_providers_ldap_ldapprovider carries search_mode, bind_mode and the id
            # ranges - no search_group), so the value that used to stand here was silently
            # ignored; and if it did exist it would restrict the directory for *every*
            # consumer, while there is one provider for the whole fleet. Who may use a service
            # is that service's decision: it declares `my.contracts.consumes.<name>.ldap` and
            # renders its own filter from it.
            authorization_flow = yamlTag "!Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]";
            invalidation_flow = yamlTag "!Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]";
          };
          permissions = map (o: {
            permission = "authentik_providers_ldap.view_ldapprovider";
            role = yamlTag "!KeyOf role_ldap_${o.safeHost}";
          }) ldapOutposts;
        }
        # The LDAP outpost config endpoint only exposes providers that are bound
        # to an application, so the provider is linked here explicitly.
        {
          model = "authentik_core.application";
          identifiers = {
            slug = "ldap";
          };
          attrs = {
            name = "LDAP Directory";
            provider = yamlTag "!KeyOf ${ldapProviderId}";
            open_in_new_tab = false;
          };
        }
      ]
      ++ lib.concatMap (o: [
        {
          model = "authentik_core.token";
          identifiers = {
            identifier = "outpost-${o.hostName}-ldap-token";
          };
          attrs = {
            intent = "api";
            # The token's value comes from SOPS and is read by the outpost from its
            # environment file. `managed = false` is what keeps those two in step: a managed
            # token is rotated by Authentik on its own schedule, while a standalone outpost
            # reads its token once at start - measured 2026-09-20, the stored value was 60
            # characters against the 48 in the secret, and the outpost answered
            # "auth_via: unauthenticated" to every config fetch, which is why it never bound
            # a listener and Jellyfin could not reach it.
            user = yamlTag "!KeyOf sa_ldap_${o.safeHost}";
            key = yamlTag "!File ${config.sops.secrets.${o.tokenSecretName}.path}";
          };
        }
        {
          model = "authentik_outposts.outpost";
          id = "outpost_ldap_${o.safeHost}";
          identifiers = {
            name = o.outpostName;
          };
          attrs = {
            type = "ldap";
            service_connection = null;
            providers = [ (yamlTag "!KeyOf ${ldapProviderId}") ];
            config = {
              authentik_host = o.coreAddress;
              authentik_host_insecure = true;
            };
          };
          permissions = [
            {
              permission = "authentik_outposts.view_outpost";
              role = yamlTag "!KeyOf role_ldap_${o.safeHost}";
            }
          ];
        }
      ]) ldapOutposts;
  };

  generatedLdapOutpostBlueprint = toBlueprintYaml "ldap-outposts-generated" ldapOutpostBlueprint;

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
