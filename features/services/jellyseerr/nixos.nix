{
  config,
  lib,
  pkgs,
  fleetConfigs,
  ...
}:
let
  cfg = config.my.features.services.jellyseerr;
  contract = config.my.contracts.provides.jellyseerr;
  containerUnit = "${config.virtualisation.oci-containers.backend}-jellyseerr.service";
  integration = contract.identity.oidc.web;
  coreLib = import ../authentik/lib/core.nix { inherit fleetConfigs; };
  core = (fleetConfigs.systems config).${coreLib.hostName (fleetConfigs.systems config)}.config;
  endpointIdentifiers = import ../../../contracts/endpoints/lib/identifiers.nix { };
  applicationSlug = endpointIdentifiers.endpointName "jellyseerr" integration.publication;
  oidcConfig = (pkgs.formats.json { }).generate "seerr-oidc.json" {
    main = {
      oidcLogin = true;
      applicationUrl = contract.publications.web.publicUrl;
    };
    provider = {
      slug = cfg.oidc.providerSlug;
      name = "Authentik";
      issuerUrl = "${core.my.contracts.provides.authentik.publications.web.publicUrl}/application/o/${applicationSlug}/";
      inherit (integration) clientId;
      scopes = lib.concatStringsSep " " integration.propertyMappings;
    };
  };
in
{
  options.my.features.services.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr Media Request Manager";
    oidc = {
      clientId = lib.mkOption {
        type = lib.types.str;
        default = "seerr";
        description = "Client identifier shared by Seerr and its declared OIDC integration.";
      };
      providerSlug = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9-]+";
        default = "authentik";
        description = "Native Seerr provider identity, preserved for existing linked accounts.";
      };
      secretPath = lib.mkOption {
        type = lib.types.str;
        default = "services/apps/seerr_oidc_secret";
        description = "SOPS path holding the dedicated OIDC client credential.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.oidc.secretPath}.restartUnits = [ "seerr-oidc-configure.service" ];
    systemd.services.seerr-oidc-configure = {
      description = "Configure Seerr's native OIDC integration";
      wantedBy = [ "multi-user.target" ];
      after = [ containerUnit ];
      requires = [ containerUnit ];
      restartTriggers = [
        oidcConfig
        ./configure-oidc.py
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 120;
        UMask = "0077";
        LoadCredential = "oidc-secret:${config.sops.secrets.${cfg.oidc.secretPath}.path}";
        ExecStart = "${pkgs.python3}/bin/python3 ${./configure-oidc.py} ${contract.endpoints.web.localUrl} /var/lib/jellyseerr/settings.json ${oidcConfig} %d/oidc-secret";
      };
    };
    # Run Jellyseerr as an OCI Container
    virtualisation.oci-containers.containers."jellyseerr" = {
      image = "ghcr.io/v3djg6gl/seerr:feat-oidc-jellyfin-quickconnect";
      extraOptions = [
        "--network=host"
      ];
      volumes = [
        "/var/lib/jellyseerr:/app/config"
      ];
      environment = {
        TZ = "Europe/Berlin";
        NODE_ENV = "production";
      };
    };

    # Ensure the config directory exists with correct permissions recursively
    systemd.tmpfiles.rules = [
      "Z /var/lib/jellyseerr 0750 1000 1000 -"
    ];

    my.contracts.provides.jellyseerr = {
      publications."web" = {
        scope = "public";
        endpoint = "web";
        auth = "oidc";
        accessGroups = [ "media-users" ];
        subdomain = "seerr";
        # Ingress reaches this over the WireGuard mesh (invariant I10).
      };
      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Medienwünsche anfragen und freigeben.";
          en = "Request and approve media.";
        };
        show = true;
        displayName = "Seerr";
        category = "Media";
        icon = "jellyseerr";
      };
      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";
      identity.oidc.web = {
        enable = true;
        publication = "web";
        inherit (cfg.oidc) clientId secretPath;
        redirectPaths = [ "/login?provider=${cfg.oidc.providerSlug}&callback=true" ];
      };
      endpoints.web = {
        port = 5055;
        protocol = "tcp";
        # Native OIDC performs the login; Caddy must not add a second forward-auth layer.
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "wireguard";
        };

      };
      storage = {
        stateDirs = [ "/var/lib/jellyseerr" ];
      };
    };
  };
}
