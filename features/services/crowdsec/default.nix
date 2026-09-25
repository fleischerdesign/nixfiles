{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.crowdsec;
  isMaster = cfg.role == "master";

  # The master as this host reaches it: the LAN address while both are at home, otherwise the overlay
  # address (lib/addresses.nix). The master normally sits in the cloud, so this is the overlay - and the
  # rule is stated once instead of here.
  addresses = import ../../../lib/addresses.nix { inherit lib; };
  masterIP = addresses.serviceAddress {
    topology = config.my.topology;
    consumer = config.my.topology.hosts.${config.networking.hostName} or null;
    peer = config.my.topology.hosts.${cfg.masterHost};
  };

  # Project scenario exemptions across all endpoints in the fleet.
  # The master/ingress host terminates or inspects traffic for all services, so we project
  # all declared exemptions from every host configuration.
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  allEndpoints = lib.concatLists (
    lib.mapAttrsToList (
      _hostName: hostConfig:
      lib.concatMap (contract: lib.attrValues (contract.endpoints or { })) (
        lib.attrValues (hostConfig.config.my.contracts.provides or { })
      )
    ) flakeConfigurations
  );

  exemptDomains = lib.unique (
    lib.concatMap (
      ep:
      let
        domains = lib.filter (d: d != null && !lib.hasInfix "*" d) (
          (lib.optional (ep.canonicalDomain != null) ep.canonicalDomain) ++ (ep.extraDomains or [ ])
        );
      in
      lib.optionals ((ep.crowdsec.exemptScenarios or [ ]) != [ ]) domains
    ) allEndpoints
  );
in
{
  options.my.features.services.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec IPS";
    masterHost = lib.mkOption {
      type = lib.types.str;
      default = "cld-edge-01";
      description = "The name of the CrowdSec master host (LAPI server) in the topology.";
    };
    role = lib.mkOption {
      type = lib.types.enum [
        "master"
        "agent"
      ];
      default = "agent";
      description = "Role of this host: master (LAPI server) or agent (client).";
    };
    excludeLogPatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Regex patterns for log files to exclude from acquisition.";
    };
    whitelist = {
      cidrs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Explicit IPv4/IPv6 CIDR ranges to globally whitelist in CrowdSec parsers.";
      };
      ips = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Explicit IPv4/IPv6 single addresses to globally whitelist in CrowdSec parsers.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.crowdsec = {
      enable = true;

      localConfig = {
        parsers.s02Enrich = [
          {
            name = "custom/trusted-internal";
            description = "Whitelist internal LAN and WireGuard mesh IPs";
            whitelist = {
              reason = "trusted internal network";
              cidr = lib.unique (config.my.topology.trustedSubnets ++ cfg.whitelist.cidrs);
              ip = cfg.whitelist.ips;
            };
          }
        ]
        ++ lib.optionals (exemptDomains != [ ]) [
          {
            name = "custom/endpoint-exemptions";
            description = "Exempt declared service endpoints from crawl/probe detections";
            whitelist = {
              reason = "contract-declared exemption for service endpoint";
              expression = map (
                domain: "evt.Meta.service == 'http' && evt.Meta.target_fqdn == '${domain}'"
              ) exemptDomains;
            };
          }
        ];
      };

      hub.collections = [
        "crowdsecurity/linux"
        "crowdsecurity/caddy"
      ];

      localConfig.acquisitions = [
        {
          filenames = [ "/var/log/caddy/access-*.log" ];
          exclude_regexps = cfg.excludeLogPatterns;
          labels.type = "caddy";
        }
        {
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
        }
      ];

      settings = {
        # Master-spezifische Server-Einstellungen
        general = lib.mkIf isMaster {
          api.server = {
            listen_uri = "0.0.0.0:8085";
            enable = true;
          };
          prometheus = {
            enabled = true;
            level = "full";
            listen_addr = "0.0.0.0";
            listen_port = 6060;
          };
        };

        # Agent-Konfiguration: Nutzt das generierte Template
        lapi.credentialsFile =
          if isMaster then
            "/etc/crowdsec/local_api_credentials.yaml"
          else
            config.sops.templates."crowdsec_lapi.yaml".path;
      };
    };

    # Firewall-Bouncer
    services.crowdsec-firewall-bouncer = {
      enable = true;
      # Disable auto-registration, we provide the key via SOPS
      registerBouncer.enable = false;
      # Official NixOS option for the API key path
      secrets.apiKeyPath = config.sops.secrets."services/crowdsec/bouncer_key".path;
      settings = {
        api_url = "http://${masterIP}:8085/";
        # api_key_file is automatically set by the module if apiKeyPath is used
      };
    };

    # Berechtigungen & User
    users.users.crowdsec.extraGroups = [
      "systemd-journal"
      "caddy"
    ];
    systemd.services.crowdsec-firewall-bouncer.serviceConfig.DynamicUser = lib.mkForce false;

    my.contracts.provides.crowdsec = lib.mkIf isMaster {
      # The local API, and the single port in this file that belongs on the mesh: every host's
      # firewall bouncer and agent registers against it (`api_url = http://${masterIP}:8085/`), and
      # `${masterIP}` is an overlay address. Leaving it undeclared is what closing the mesh broke -
      # measured: the master listened on 8085 and nothing could reach it, silently.
      endpoints.lapi = {
        port = 8085;
        protocol = "tcp";
        scope = "mesh";
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
      };
      endpoints.web = {
        port = 6060;
        protocol = "tcp";
        scope = "internal";
        # The metrics of the local API, scraped by the collector on this host.
        directAccess = {
          enable = true;
          interface = "local";
          protocol = "tcp";
        };
        monitoring = {
          http.enable = false;
          scrape.enable = true;
          scrape.port = 6060;
        };
      };
    };

    # Secrets
    sops.secrets."services/crowdsec/bouncer_key" = {
      owner = "root";
      restartUnits = [ "crowdsec-firewall-bouncer.service" ];
    };

    # Nur Agents brauchen das Passwort für den Master
    sops.secrets."services/crowdsec/agent_password" = lib.mkIf (!isMaster) {
      owner = "crowdsec";
    };

    # Generiere die Credentials-Datei dynamisch
    sops.templates."crowdsec_lapi.yaml" = lib.mkIf (!isMaster) {
      owner = "crowdsec";
      content = ''
        url: http://${masterIP}:8085/
        login: ${config.networking.hostName}
        password: ${config.sops.placeholder."services/crowdsec/agent_password"}
      '';
    };
  };
}
