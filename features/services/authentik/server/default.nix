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

  authEndpoints = lib.concatMapAttrs (
    _: host:
    lib.filterAttrs (_: v: v.proxy.enable && v.proxy.auth && v.canonicalDomain != null) (
      host.config.my.endpoints or { }
    )
  ) flakeConfigurations;

  sortedEndpointNames = lib.sort (a: b: a < b) (builtins.attrNames authEndpoints);

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

  generatedProxyJson = pkgs.writeText "proxy-apps-generated.json" (builtins.toJSON proxyBlueprint);

  # Merged blueprints directory containing static base blueprints and generated proxy applications
  effectiveBlueprintsDir = pkgs.runCommandLocal "authentik-blueprints" { } ''
    mkdir -p "$out"
    cp -r ${./blueprints}/* "$out/"
    chmod -R u+w "$out"
    mkdir -p "$out/03-apps"
    cp ${generatedProxyJson} "$out/03-apps/proxy-apps-generated.json"
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
        EnvironmentFile = config.sops.secrets."services/authentik/core_env".path;
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
        EnvironmentFile = config.sops.secrets."services/authentik/core_env".path;
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
    };

    # 4. Database Setup (Ensure DB exists)
    services.postgresql = {
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        {
          name = "authentik";
          ensureDBOwnership = true;
        }
      ];
    };

    # 5. Reverse Proxy
    my.endpoints.authentik = {
      host = config.networking.hostName;
      port = 9055;
      proxy = {
        enable = true;
        inherit (cfg) domain;
      };
      monitoring = {
        scrape.enable = true;
        scrape.port = 9300;
      };
    };

    # 6. Secrets
    sops.secrets."services/authentik/core_env" = {
      owner = "authentik";
    };
  };
}
