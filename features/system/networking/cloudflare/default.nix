# features/system/networking/cloudflare/default.nix
# Declarative Cloudflare Edge & DNS GitOps Engine (SOLID & Agentless Architecture).
# Reconciles Cloudflare DNS records and Edge TLS settings idempotently from `my.topology` and `my.endpoints`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.cloudflare;
  topology = config.my.topology;
  edgeHost = topology.hosts.cld-edge-01 or null;
  opsHost = topology.hosts.cld-ops-01 or null;

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

  # Synthesize default DNS records from topology and endpoints.
  # Default to `proxied = false` (DNS-only) to guarantee full compatibility with
  # CrowdSec kernel nftables firewall bouncers, Caddy ACME DNS-01 challenges,
  # unlimited body upload sizes (Paperless), and uninterrupted WebSocket/AI streams.
  defaultRecords =
    lib.optional (edgeHost != null && edgeHost.ipv4 != null) {
      name = "@";
      type = "A";
      content = edgeHost.ipv4;
      proxied = false;
      ttl = 1;
      comment = "Root Ingress -> cld-edge-01 (DNS-only for CrowdSec)";
    }
    ++ lib.optional (edgeHost != null && edgeHost.ipv4 != null) {
      name = "edge";
      type = "A";
      content = edgeHost.ipv4;
      proxied = false; # Unproxied for direct SSH & WireGuard handshakes
      ttl = 1;
      comment = "Direct Edge Host -> cld-edge-01";
    }
    ++ lib.optional (opsHost != null && opsHost.ipv4 != null) {
      name = "ops";
      type = "A";
      content = opsHost.ipv4;
      proxied = false; # Unproxied for direct WireGuard & Telemetry
      ttl = 1;
      comment = "Direct Ops Host -> cld-ops-01";
    }
    ++ lib.optional (edgeHost != null && edgeHost.ipv4 != null) {
      name = "*";
      type = "CNAME";
      content = "edge.${topology.domain}";
      proxied = false;
      ttl = 1;
      comment = "Wildcard Ingress -> edge.vyrx.de (DNS-only)";
    };

  # Render desired state configuration as JSON derivation
  desiredStateJson = pkgs.writeText "cloudflare-desired-state.json" (
    builtins.toJSON {
      domain = cfg.domain;
      settings = {
        ssl = cfg.settings.ssl;
        always_use_https = if cfg.settings.alwaysUseHttps then "on" else "off";
        min_tls_version = cfg.settings.minTlsVersion;
      };
      records = cfg.records;
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
      default = defaultRecords;
      description = "Declarative list of DNS records to enforce";
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
