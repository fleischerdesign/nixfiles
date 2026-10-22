# features/system/networking/cloudflare/nixos.nix
# Declarative Cloudflare Edge & DNS GitOps Engine (SOLID & Agentless Architecture).
# Reconciles Cloudflare DNS records and Edge TLS settings idempotently from the single
# sources of truth `my.topology` (host addressing) and `my.contracts.provides`
# (service endpoints) — service records are never hand-maintained.
{
  config,
  lib,
  fleetConfigs,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.system.networking.cloudflare;
  topology = config.my.topology;

  # Fleet-wide configuration graph. `flake` is injected as a module specialArg by
  # lib/mk-system.nix; the fallback keeps this module evaluable standalone.
  flakeConfigurations = fleetConfigs.systems config;

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
  # Public DNS is *derived*; nothing here is hand-maintained, and nothing outside the public
  # plane is ever published (Naming spec §1, §5.1).
  #   1. ingressRecords   -> zone apex (and, opt-in, a catch-all) on the ingress host
  #   2. nodeRecords      -> every host as <hostname>.node.<domain> to its overlay address
  #   3. endpointRecords  -> every `public` endpoint on its derived FQDN, ingress-terminated
  # The transitional legacy role labels (`edge.vyrx.de`, `ops.vyrx.de`) are gone with their
  # source: the per-host domain field carried a second naming scheme next to the normative
  # `node` plane, and it did not even contain the host name it claimed to label.

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
  ingressIsPublic = ingressHost != null && isPublicIpv4 ingressHost.ipv4;

  ingressRecords = lib.optionals ingressIsPublic (
    [ (mkRecord "Zone apex -> ${cfg.ingressHost}" "@" "A" ingressHost.ipv4) ]
    ++ lib.optionals cfg.catchAll [
      (mkRecord "Wildcard ingress -> ${cfg.ingressHost}" "*" "CNAME" ingressHost.domain)
    ]
  );

  # <hostname>.node.<domain> -> overlay address (docs/architecture.md §3.3). An `A` record is the
  # correct encoding: a CNAME may not point at an IP address.
  nodeRecords = lib.concatLists (
    lib.mapAttrsToList (
      hostName: host:
      lib.optional (host.wireguardIpv4 != null) (
        mkRecord "Node management ${hostName}" "${hostName}.node" "A" host.wireguardIpv4
      )
    ) topology.hosts
  );

  # A device in a carried zone is reachable over the mesh, so its name belongs on the same `node` plane
  # as the hosts - with the one address the device has. This is the same kind of record as `nodeRecords`
  # above: a private address in public DNS. It tells a member where the device is and tells everyone else
  # nothing they can act on, because the address is unrouted outside the overlay. The predicate is the
  # zone, not the access: a carried device is published whether or not it declares a port, because the
  # question this answers is "where is it", and access is declared per port on the device itself.
  deviceRecords = lib.concatLists (
    lib.mapAttrsToList (
      deviceName: device:
      lib.optional (builtins.elem device.zone topology.announcedZones) (
        mkRecord "Carried device ${deviceName}" "${deviceName}.node" "A" device.ipv4
      )
    ) topology.devices
  );

  # Every `public` endpoint resolves to the *ingress*, which terminates TLS and proxies to the
  # provider over the WireGuard mesh (docs/architecture.md §7.1). The provider host does **not**
  # need a public address -- that is the whole point of the ingress engine.
  endpointRecords = lib.concatLists (
    lib.mapAttrsToList (
      hostName: hostConfig:
      lib.concatLists (
        lib.mapAttrsToList (
          _svcName: contract:
          lib.concatMap (
            pub:
            let
              mk = mkRecord "Service ${hostName}";
              names =
                lib.optionals (pub.scope == "public" && pub.canonicalDomain != null) [
                  pub.canonicalDomain
                ]
                ++ lib.optionals (pub.scope == "public") (lib.filter inZone pub.extraDomains);
            in
            lib.optionals ingressIsPublic (map (n: mk n "A" ingressHost.ipv4) names)
          ) (lib.attrValues contract.publications)
        ) (fleetConfigs.providesOf hostConfig)
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
      }) (ingressRecords ++ nodeRecords ++ deviceRecords ++ endpointRecords ++ extraRecords)
    )
  );

  # The same records in nod's provider format (ADR-030): `resources` with
  # `kind`, `id` and `attributes`. Derived from the same projections, never a
  # second source of truth. Cloudflare reports absolute names, the declaration
  # uses `@` and relative labels, so the projection normalises to the names
  # the API reports.
  nodFqdn =
    name:
    if name == "@" then
      cfg.domain
    else if name == cfg.domain || lib.hasSuffix ".${cfg.domain}" name then
      name
    else
      "${name}.${cfg.domain}";

  nodDesiredState = pkgs.writeText "cloudflare-nod-desired.json" (
    builtins.toJSON {
      resources = [
        {
          kind = "zone.settings";
          id = "zone.settings";
          attributes = {
            ssl = cfg.settings.ssl;
            always_use_https = if cfg.settings.alwaysUseHttps then "on" else "off";
            min_tls_version = cfg.settings.minTlsVersion;
          };
        }
      ]
      ++ map (r: {
        kind = "dns.record";
        id = "${r.type}:${nodFqdn r.name}";
        attributes = {
          type = r.type;
          name = nodFqdn r.name;
          content = r.content;
          ttl = r.ttl;
          proxied = r.proxied;
        };
      }) projectedRecords;
    }
  );

  nodSettings = pkgs.writeText "cloudflare-nod-settings.json" (
    builtins.toJSON {
      zone = cfg.domain;
      token_env = "CLOUDFLARE_API_TOKEN";
    }
  );

  nodPkg = inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.default;
  nodProvider = inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.nod-provider-cloudflare;

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
      default = topology.ingressHost;
      description = "Topology host that terminates public ingress traffic (defaults to my.topology.ingressHost).";
    };

    catchAll = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Publish a `*.<zone>` catch-all to the ingress. Off by default: unknown names — including
        the internal planes — then return NXDOMAIN instead of leaking to the ingress
        (Naming spec §5.1, option A).
      '';
    };

    observeOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run only the read-only nod observation on this host. The writer service and
        timer stay off, so exactly one host owns the zone. Used to observe from the
        reconciler host without creating a second writer.
      '';
    };

    nodDesiredStateFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${nodDesiredState}";
      description = ''
        The record declaration in nod's provider format. The flake's `nod`
        output points at this path; the observer already puts it in the
        system closure.
      '';
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

  };

  config = lib.mkIf cfg.enable {
    my.features.system.networking.cloudflare.effectiveRecords = projectedRecords ++ cfg.records;

    # Ensure SOPS token is accessible
    sops.secrets.${cfg.apiTokenSecret} = lib.mkDefault { };

    # The provider reads its credential from the environment; the value comes
    # from SOPS through a template, never from the Nix store or argv.
    sops.templates."nod-cloudflare.env".content = ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder.${cfg.apiTokenSecret}}
    '';

    # Stage 0 of the provider rollout (ADR-030): observe and plan, never apply.
    # It runs where the zone's data already lives, uses the existing token and
    # logs the report; the daemon is not involved, so no second writer exists.
    systemd.services.nod-cloudflare-observe = {
      description = "Read-only Cloudflare observation with nod (ADR-030 stage 0)";
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment.NOD_AUDIT_PATH = "/var/lib/nod-cloudflare-observe/history.json";
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "nod-cloudflare-observe";
        EnvironmentFile = config.sops.templates."nod-cloudflare.env".path;
        ExecStart = lib.escapeShellArgs [
          "${nodPkg}/bin/nod"
          "reconcile"
          "--flake"
          "/var/lib/nod-cloudflare-observe"
          "--command"
          "${nodProvider}/bin/nod-provider-cloudflare"
          "--desired"
          "${nodDesiredState}"
          "--settings"
          "${nodSettings}"
          "--state-dir"
          "/var/lib/nod-cloudflare-observe"
          "--env"
          "CLOUDFLARE_API_TOKEN"
        ];
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

  };
}
