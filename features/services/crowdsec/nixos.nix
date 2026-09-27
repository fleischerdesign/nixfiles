{
  config,
  lib,
  fleetConfigs,
  pkgs,
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
  flakeConfigurations = fleetConfigs.systems config;

  allPublications = lib.concatLists (
    lib.mapAttrsToList (
      _hostName: hostConfig:
      lib.concatMap (contract: lib.attrValues (contract.publications or { })) (
        lib.attrValues (fleetConfigs.providesOf hostConfig)
      )
    ) flakeConfigurations
  );

  exemptDomains = lib.unique (
    lib.concatMap (
      pub:
      let
        domains = lib.filter (d: d != null && !lib.hasInfix "*" d) (
          (lib.optional (pub.canonicalDomain != null) pub.canonicalDomain) ++ (pub.extraDomains or [ ])
        );
      in
      lib.optionals ((pub.crowdsec.exemptScenarios or [ ]) != [ ]) domains
    ) allPublications
  );
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.publications = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                crowdsec = {
                  exemptScenarios = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = ''
                      List of CrowdSec scenario names that are explicitly exempted from triggering bans
                      when accessing this endpoint (e.g. ['crowdsecurity/http-crawl-non_statics'] for binary caches).
                    '';
                  };
                };

              };
            }
          );
        };
      }
    );
  };

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
    # The upstream NixOS module links declarative parsers using their /nix/store/<hash>-...
    # path directly into /etc/crowdsec/parsers/s02-enrich/ via systemd-tmpfiles without pruning
    # old generations. CrowdSec discards duplicate parsers when multiple hashed copies accumulate,
    # causing whitelist parsers to be silently ignored. We purge broken and stale store links.
    systemd.services.crowdsec.serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.writeShellScript "crowdsec-prune-stale-parsers" ''
        for dir in /etc/crowdsec/parsers/*; do
          [ -d "$dir" ] || continue
          for link in "$dir"/*; do
            [ -L "$link" ] || continue
            target="$(readlink "$link")" || continue
            case "$target" in
              /nix/store/*)
                if [ ! -e "$link" ]; then
                  rm -f "$link"
                fi
                ;;
            esac
          done
        done
      ''}"
    ];

    systemd.services.crowdsec-firewall-bouncer.serviceConfig.DynamicUser = lib.mkForce false;

    my.contracts.provides.crowdsec = lib.mkIf isMaster {
      telemetry.probes."lapi-http".endpoint = "lapi";
      telemetry.probes."lapi-http".kind = "http";
      telemetry.scrapes."web-metrics".endpoint = "web";
      # The local API, and the single port in this file that belongs on the mesh: every host's
      # firewall bouncer and agent registers against it (`api_url = http://${masterIP}:8085/`), and
      # `${masterIP}` is an overlay address. Leaving it undeclared is what closing the mesh broke -
      # measured: the master listened on 8085 and nothing could reach it, silently.
      endpoints.lapi = {
        port = 8085;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
      };
      endpoints.web = {
        port = 6060;
        protocol = "tcp";
        # The metrics of the local API, scraped by the collector on this host.
        directAccess = {
          enable = true;
          interface = "local";
          protocol = "tcp";
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
