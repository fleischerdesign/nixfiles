{
  config,
  lib,
  fleetConfigs,
  pkgs,
  ...
}:
let
  serviceAddressLib = import ../../../contracts/topology/lib/service-address.nix { };
  cfg = config.my.features.services.crowdsec;
  isMaster = cfg.role == "master";

  # The master as this host reaches it: the LAN address while both are at home, otherwise the overlay
  # address (the topology contract). The master normally sits in the cloud, so this is the overlay - and the
  # rule is stated once instead of here.
  masterIP = serviceAddressLib.serviceAddress {
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
      default = fleetConfigs.uniqueHost {
        systems = fleetConfigs.systems config;
        matches = hostCfg: (hostCfg.my.features.services.crowdsec.role or "agent") == "master";
        role = "crowdsec master";
      };
      description = "The CrowdSec master host (LAPI server) in the topology. Derived as the single host with the master role; an explicit override must name a master-role host.";
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
    assertions = [
      {
        assertion =
          let
            masterCfg = (fleetConfigs.systems config).${cfg.masterHost}.config or null;
          in
          masterCfg != null && (masterCfg.my.features.services.crowdsec.role or "agent") == "master";
        message = "crowdsec: masterHost '${cfg.masterHost}' on ${config.networking.hostName} is not a host with the master role";
      }
    ];

    services.crowdsec = {
      enable = true;

      settings = {
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

        acquisitions = [
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

        # Der Master liest die lokal erzeugten Credentials, der Agent das Template.
        config = lib.mkMerge [
          (lib.mkIf isMaster {
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
          })
          {
            # The previous module disabled the local API on an agent; the restructured one enables
            # it and binds 127.0.0.1:8080, which is taken on hosts that run an agent. Only the
            # master publishes an API.
            api.server.enable = isMaster;
            api.client.credentials_path =
              if isMaster then
                "/etc/crowdsec/local_api_credentials.yaml"
              else
                config.sops.templates."crowdsec_lapi.yaml".path;
          }
          # The module defaults data_dir to /var/lib/crowdsec/data; the state this host accumulated
          # lives under /var/lib/crowdsec/state. Leaving the default moves the database and the hub
          # out from under the engine, which then exits on missing hub data. Pin the layout.
          {
            config_paths = {
              config_dir = "/etc/crowdsec";
              data_dir = "/var/lib/crowdsec/state";
              hub_dir = "/var/lib/crowdsec/state/hub";
            };
          }
        ];
      };

      hub.collections = [
        "crowdsecurity/linux"
        "crowdsecurity/caddy"
      ];
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
    # A declarative parser reaches /etc/crowdsec through systemd-tmpfiles, and a link into the
    # store carries the store hash in its name, so every generation adds a file next to the last
    # one instead of replacing it. CrowdSec keeps the first parser it reads per name and discards
    # the rest, so an old copy silently wins over the one in the repository. The module now writes
    # `<index>-nixos-generated.yaml`; every link named after an earlier scheme is a leftover.
    systemd.services.crowdsec.serviceConfig.ExecStartPre = lib.mkBefore [
      "${pkgs.writeShellScript "crowdsec-prune-stale-parsers" ''
        legacy="parsers-s00-raw.yaml parsers-s01-parse.yaml parsers-s02-enrich.yaml postoverflows-s01-whitelist.yaml scenario.yaml context.yaml notification.yaml"

        for dir in \
          /etc/crowdsec/parsers/* \
          /etc/crowdsec/postoverflows/* \
          /etc/crowdsec/scenarios \
          /etc/crowdsec/contexts \
          /etc/crowdsec/notifications; do
          [ -d "$dir" ] || continue
          for link in "$dir"/*; do
            [ -L "$link" ] || continue
            target="$(readlink "$link")" || continue
            case "$target" in
              /nix/store/*) ;;
              *) continue ;;
            esac

            # A dangling link is dead whatever its name.
            if [ ! -e "$link" ]; then
              rm -f "$link"
              continue
            fi

            base="$(basename "$link")"
            for name in $legacy; do
              case "$base" in
                *"-$name")
                  rm -f "$link"
                  echo "pruned legacy crowdsec link $link" >&2
                  break
                  ;;
              esac
            done
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
