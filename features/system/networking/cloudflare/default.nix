# features/system/networking/cloudflare/default.nix
# Declarative Cloudflare Edge & DNS GitOps Engine (SOLID & Agentless Architecture).
# Reconciles Cloudflare DNS records and Edge TLS settings idempotently from the single
# sources of truth `my.topology` (host addressing) and `my.contracts.provides`
# (service endpoints) — service records are never hand-maintained.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.cloudflare;
  topology = config.my.topology;

  # Fleet-wide configuration graph. `flake` is injected as a module specialArg by
  # lib/core/system-builder.nix; the fallback keeps this module evaluable standalone.
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  # Submodule for a declarative DNS record
  recordSubmodule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Fully qualified domain name or subdomain (e.g. '@', 'edge', 'auth.vyrx.de')";
      };
      type = lib.mkOption {
        type = lib.types.enum [
          "A"
          "AAAA"
          "CNAME"
          "TXT"
        ];
        default = "A";
        description = "DNS record type";
      };
      content = lib.mkOption {
        type = lib.types.str;
        description = "Record destination (IP address or canonical target)";
      };
      proxied = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether traffic is proxied through Cloudflare CDN/WAF";
      };
      ttl = lib.mkOption {
        type = lib.types.int;
        default = 1; # 1 = Auto in Cloudflare
        description = "TTL in seconds (1 = Automatic)";
      };
      comment = lib.mkOption {
        type = lib.types.str;
        default = "Managed by VYRX GitOps";
        description = "Descriptive tag to identify managed records";
      };
    };
  };

  # --- SSOT projections -----------------------------------------------------
  #
  # DNS is *derived*, never hand-maintained:
  #   1. ingressRecords  -> zone apex + catch-all wildcard to the declared ingress host
  #   2. hostRecords     -> every publicly addressed host on its topology domain
  #   3. endpointRecords -> every `public` contract endpoint on its provider host

  # RFC 1918 / loopback / link-local addresses are never authoritative in public DNS.
  isPublicIpv4 =
    ip:
    ip != null
    && !(
      lib.hasPrefix "10." ip
      || lib.hasPrefix "192.168." ip
      || lib.hasPrefix "127." ip
      || lib.hasPrefix "169.254." ip
      || builtins.match "172\\.(1[6-9]|2[0-9]|3[01])\\..*" ip != null
    );

  inZone = fqdn: fqdn != null && (fqdn == cfg.domain || lib.hasSuffix ".${cfg.domain}" fqdn);

  mkRecord = comment: name: type: content: {
    inherit
      name
      type
      content
      comment
      ;
    # DNS-only (proxied = false): CrowdSec nftables bouncers, ACME DNS-01,
    # unlimited uploads and uninterrupted WebSocket/AI streams.
    proxied = false;
    ttl = 1;
  };

  ingressHost = topology.hosts.${cfg.ingressHost} or null;
  ingressIsPublic =
    ingressHost != null && ingressHost.domain != null && isPublicIpv4 ingressHost.ipv4;

  ingressRecords = lib.optionals ingressIsPublic [
    (mkRecord "Zone apex -> ${cfg.ingressHost}" "@" "A" ingressHost.ipv4)
    (mkRecord "Wildcard ingress -> ${cfg.ingressHost}" "*" "CNAME" ingressHost.domain)
  ];

  hostRecords = lib.concatLists (
    lib.mapAttrsToList (
      hostName: host:
      lib.optional (isPublicIpv4 host.ipv4 && inZone host.domain) (
        mkRecord "Host ${hostName} (topology)" host.domain "A" host.ipv4
      )
    ) topology.hosts
  );

  endpointRecords = lib.concatLists (
    lib.mapAttrsToList (
      hostName: hostConfig:
      let
        host = topology.hosts.${hostName} or null;
      in
      lib.optionals (host != null && isPublicIpv4 host.ipv4) (
        lib.concatLists (
          lib.mapAttrsToList (
            _svcName: contract:
            lib.concatMap (
              ep:
              let
                mk = mkRecord "Service ${hostName}";
              in
              lib.optional (ep.scope == "public" && ep.canonicalDomain != null && inZone ep.canonicalDomain) (
                mk ep.canonicalDomain "A" host.ipv4
              )
              ++ lib.optionals (ep.scope == "public") (
                map (alias: mk alias "A" host.ipv4) (lib.filter inZone ep.extraDomains)
              )
            ) (lib.attrValues contract.endpoints)
          ) (hostConfig.config.my.contracts.provides or { })
        )
      )
    ) flakeConfigurations
  );

  # Escape hatch for names that cannot be contract-derived (e.g. a host-level
  # Caddy redirect alias). Keep empty whenever possible.
  extraRecords = [ ];

  # Deterministically deduplicate by (type, fqdn); `@` and the zone apex are the
  # same name, and identical definitions collapse (first definition wins).
  projectedRecords = lib.attrValues (
    builtins.listToAttrs (
      map (r: {
        name = "${r.type}:${if r.name == cfg.domain then "@" else r.name}";
        value = r;
      }) (ingressRecords ++ hostRecords ++ endpointRecords ++ extraRecords)
    )
  );

  # Render desired state configuration as JSON derivation
  desiredStateJson = pkgs.writeText "cloudflare-desired-state.json" (
    builtins.toJSON {
      domain = cfg.domain;
      settings = {
        ssl = cfg.settings.ssl;
        always_use_https = if cfg.settings.alwaysUseHttps then "on" else "off";
        min_tls_version = cfg.settings.minTlsVersion;
      };
      records = cfg.effectiveRecords;
    }
  );

  # Python reconciliation engine script wrapper
  syncScript = pkgs.writeShellScriptBin "cloudflare-sync" ''
    exec ${pkgs.python3}/bin/python3 ${./sync.py} --spec ${desiredStateJson} "$@"
  '';
in
{
  options.my.features.system.networking.cloudflare = {
    enable = lib.mkEnableOption "Declarative Cloudflare Edge & DNS GitOps Engine";

    domain = lib.mkOption {
      type = lib.types.str;
      default = topology.domain;
      description = "Primary root zone managed in Cloudflare";
    };

    ingressHost = lib.mkOption {
      type = lib.types.str;
      default = "cld-edge-01";
      description = "Topology host that terminates zone-apex and catch-all wildcard ingress traffic.";
    };

    apiTokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "infra/cloudflare_api_token";
      description = "SOPS secret identifier containing the Cloudflare API token";
    };

    settings = {
      ssl = lib.mkOption {
        type = lib.types.enum [
          "off"
          "flexible"
          "full"
          "strict"
        ];
        default = "strict";
        description = "SSL/TLS encryption mode";
      };

      alwaysUseHttps = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enforce HTTP -> HTTPS redirection at the Cloudflare Edge";
      };

      minTlsVersion = lib.mkOption {
        type = lib.types.enum [
          "1.0"
          "1.1"
          "1.2"
          "1.3"
        ];
        default = "1.3";
        description = "Minimum allowed TLS version for client connections";
      };
    };

    records = lib.mkOption {
      type = lib.types.listOf recordSubmodule;
      default = [ ];
      description = "Additional DNS records appended to the topology/contract projection (escape hatch; prefer contracts).";
    };

    effectiveRecords = lib.mkOption {
      type = lib.types.listOf recordSubmodule;
      readOnly = true;
      description = "The fully reconciled record set (topology/contract projection + operator extras).";
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd timer oncalendar interval for automated state reconciliation";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = syncScript;
      readOnly = true;
      description = "The compiled cloudflare-sync executable package";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.system.networking.cloudflare.effectiveRecords = projectedRecords ++ cfg.records;

    # Expose cloudflare-sync in system packages
    environment.systemPackages = [ cfg.package ];

    # Ensure SOPS token is accessible
    sops.secrets.${cfg.apiTokenSecret} = lib.mkDefault { };

    # Systemd periodic reconciliation timer
    systemd.services.cloudflare-dns-sync = {
      description = "Declarative Cloudflare Edge & DNS Reconciliation";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/cloudflare-sync --token-file ${
          config.sops.secrets.${cfg.apiTokenSecret}.path
        }";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.cloudflare-dns-sync = {
      description = "Periodic Cloudflare Edge & DNS Reconciliation Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.syncInterval;
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };
  };
}
