{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.authentik.server;
  authentikPackage = pkgs.authentik;

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

  # Declarative model-driven blueprint compiling all auth endpoints into Authentik ProxyProviders and Applications
  proxyBlueprint = {
    version = 1;
    metadata = {
      name = "vyrx-apps-proxy";
    };
    entries =
      (lib.concatMap (
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
              authorization_flow = "!Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]";
            };
          }
          {
            model = "authentik_core.application";
            identifiers = {
              slug = name;
            };
            attrs = {
              name = displayName;
              provider = "!Key provider_proxy_${safeId}";
              meta_launch_url = "https://${ep.canonicalDomain}";
              inherit group;
              open_in_new_tab = true;
            };
          }
        ]
      ) sortedEndpointNames)
      ++ [
        {
          model = "authentik_core.user";
          id = "sa_proxy";
          identifiers = {
            username = "ak-outpost-proxy";
          };
          attrs = {
            name = "Service Account Proxy Outpost";
            type = "service_account";
          };
        }
        {
          model = "authentik_core.token";
          identifiers = {
            identifier = "outpost-proxy-token";
          };
          attrs = {
            intent = "app_password";
            user = "!Key sa_proxy";
            key = "!Env AUTHENTIK_OUTPOST_PROXY_TOKEN";
          };
        }
        {
          model = "authentik_outposts.outpost";
          id = "vyrx_proxy_outpost";
          identifiers = {
            name = "vyrx-proxy-outpost";
          };
          attrs = {
            type = "proxy";
            service_connection = null;
            providers = map (
              name:
              let
                safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
              in
              "!Key provider_proxy_${safeId}"
            ) sortedEndpointNames;
            config = {
              authentik_host = "https://${cfg.domain}";
              authentik_host_browser = "https://${cfg.domain}";
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
    entries = lib.concatMap (
      name:
      let
        ep = oidcEndpoints.${name};
        displayName = if ep.displayName != null then ep.displayName else name;
        group = if ep.group != null then ep.group else "Applications";
        safeId = builtins.replaceStrings [ "-" ] [ "_" ] name;
        secretAttr =
          if ep.oidc.clientSecretEnv != null then
            "!Env ${ep.oidc.clientSecretEnv}"
          else if ep.oidc.clientSecret != null then
            ep.oidc.clientSecret
          else
            "!Env AUTHENTIK_OIDC_${lib.toUpper safeId}_SECRET";
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
            authorization_flow = "!Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]";
            redirect_uris = ep.oidc.redirectUris;
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
            provider = "!Key provider_${safeId}";
            meta_launch_url = launchUrl;
            inherit group;
            open_in_new_tab = true;
          };
        }
      ]
    ) sortedOidcEndpointNames;
  };

  generatedProxyJson = pkgs.writeText "proxy-apps-generated.json" (builtins.toJSON proxyBlueprint);
  generatedOidcJson = pkgs.writeText "oidc-apps-generated.json" (builtins.toJSON oidcBlueprint);

  # Merged blueprints directory containing upstream base blueprints, custom blueprints and generated applications
  effectiveBlueprintsDir = pkgs.runCommandLocal "authentik-blueprints" { } ''
    mkdir -p "$out"
    # 1. Inherit upstream system and default blueprints (required for initial flows and setup)
    cp -r ${authentikPackage}/blueprints/* "$out/"
    chmod -R u+w "$out"

    # 2. Overlay VYRX custom blueprints
    cp -r ${./blueprints}/* "$out/"

    # 3. Inject compiled application blueprints
    mkdir -p "$out/03-apps"
    cp ${generatedProxyJson} "$out/03-apps/proxy-apps-generated.json"
    cp ${generatedOidcJson} "$out/03-apps/oidc-apps-generated.json"
  '';

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pyyaml
  ]);

  syncScript = pkgs.writeShellScriptBin "authentik-sync" ''
    exec ${pythonEnv}/bin/python3 ${./sync.py} --blueprints-dir ${effectiveBlueprintsDir} "$@"
  '';
in
{
  options.my.features.services.authentik.server = {
    enable = lib.mkEnableOption "Authentik Identity Provider (Server)";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "auth.vyrx.de";
      description = "FQDN of the Authentik identity server.";
    };
    blueprintsDir = lib.mkOption {
      type = lib.types.package;
      default = effectiveBlueprintsDir;
      readOnly = true;
      description = "Compiled directory of static and dynamically compiled Authentik blueprints";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = syncScript;
      readOnly = true;
      description = "The compiled authentik-sync reconciliation package";
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
          # Listen on 9055 (to avoid conflict with ClickHouse)
          "AUTHENTIK_LISTEN__HTTP=0.0.0.0:9055"
          "AUTHENTIK_LISTEN__METRICS=0.0.0.0:9300"
          "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,100.64.0.0/10"
          "AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true"
          "AUTHENTIK_AVATARS=gravatar"
          "AUTHENTIK_EVENTS__CONTEXT_PROCESSORS__GEOIP=/var/lib/GeoIP/GeoLite2-City.mmdb"
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
        port = 9055;
        protocol = "tcp";
        scope = "public";
        auth = "none";
        inherit (cfg) domain;
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
