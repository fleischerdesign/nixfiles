{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.services.openclaw;
  runtime = import ./runtime.nix { inherit lib pkgs; };
  ingress = config.my.topology.hosts.${config.my.topology.ingressHost};
  make =
    name: instance:
    let
      id = "openclaw-${name}";
      user = id;
      # One identity file per gateway, whichever way it arrives: a SOPS secret this feature owns
      # (preferred, and what a person's gateway uses) or a path the operator provides. Everything
      # below - the fleet SSH config, Git over SSH and node-pairing verification - reads this one
      # path, so the credential cannot be named differently in two places.
      identityFile =
        if instance.fleet.privateKeySecret != null then
          config.sops.secrets.${instance.fleet.privateKeySecret}.path
        else
          instance.fleet.privateKeyFile;
      hasFleetCredential = identityFile != null;
      contract = config.my.contracts.provides.${id};
      credentials = lib.mapAttrs (
        variable: _: config.sops.templates."${id}-${variable}".path
      ) instance.secrets;
      socketDir = "/run/openclaw-publishing-${name}/sockets";
      publishingDomain =
        lib.removePrefix "*."
          config.my.contracts.provides."${id}-publishing".publications.web.canonicalDomain;
      routerSource = pkgs.writeText "${id}-publishing.Caddyfile" ''
        {
          admin off
          auto_https off
        }
        :${toString instance.publishing.port} {
          bind ${config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4}
          map {host} {application} {
            ~^([a-z0-9][a-z0-9-]{0,62})\.${lib.escapeRegex publishingDomain}$ "''${1}"
            default ""
          }
          @app expression `{application} != ""`
          handle @app {
            reverse_proxy unix/${socketDir}/{application}.sock
          }
          respond "Unknown published application" 404
        }
      '';
      routerConfig = pkgs.runCommand "${id}-publishing.Caddyfile-formatted" { } ''
        cp ${routerSource} "$out"
        chmod u+w "$out"
        ${pkgs.caddy}/bin/caddy fmt --overwrite "$out"
      '';
      built = runtime.build {
        inherit id;
        inherit (instance) stateDir;
        package = cfg.package;
        runtime = instance // {
          packages =
            instance.packages
            ++
              lib.optional instance.google.enable
                inputs.openclaw.inputs.nix-openclaw-tools.packages.${pkgs.stdenv.hostPlatform.system}.gogcli;
          skillDirectories = instance.skillDirectories ++ lib.optional instance.publishing.enable ./skills;
          credentialFiles =
            instance.credentialFiles
            // credentials
            // lib.optionalAttrs instance.google.enable {
              GOG_KEYRING_PASSWORD = "${instance.stateDir}/google/keyring-password";
            };
          environment =
            instance.environment
            // {
              HOME = instance.stateDir;
            }
            // lib.optionalAttrs instance.google.enable {
              GOG_CONFIG_DIR = "${instance.stateDir}/google";
              GOG_KEYRING_BACKEND = "file";
            }
            // lib.optionalAttrs hasFleetCredential {
              GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -F /etc/openclaw/${id}.ssh";
            }
            // lib.optionalAttrs instance.publishing.enable {
              OPENCLAW_SOCKET_DIR = socketDir;
              OPENCLAW_PUB_DOMAIN = publishingDomain;
            };
        };
        settings = lib.recursiveUpdate instance.settings (
          {
            gateway = {
              mode = "local";
              # Native local administration targets loopback, while nodes and ingress use
              # WireGuard. The endpoint contract admits only those mesh sources externally.
              bind = "lan";
              port = instance.port;
              publicOrigin = contract.publications.web.publicUrl;
              trustedProxies = [ ingress.wireguardIpv4 ];
              auth = {
                mode = "trusted-proxy";
                identityScopes.${instance.owner} = [
                  "operator.admin"
                  # Approving a node's declared capability surface is an `operator.pairing`
                  # operation; non-exec commands on that surface additionally need `operator.write`.
                  # Without these the Control UI identity cannot approve its own devices.
                  "operator.pairing"
                  "operator.write"
                ];
                trustedProxy = {
                  userHeader = "x-authentik-username";
                  requiredHeaders = [
                    "x-forwarded-for"
                    "x-forwarded-proto"
                    "x-forwarded-host"
                  ];
                  allowUsers = [ instance.owner ];
                  allowLoopback = false;
                  deviceAutoApprove.enabled = true;
                };
              };
              # Device pairing, capability approval and their auto-approval paths (docs/gateway/pairing).
              #
              # A node presents a signed device identity on connect; there is no Nix-only way to mint one.
              # `autoApproveCidrs` admits the first pairing declaratively from the mesh, and nothing else -
              # role, scope, metadata and public-key upgrades always prompt, and browsers/UI never auto-
              # approve. The declared *capability surface* is a separate decision: `sshVerify` approves it
              # automatically only by proving machine ownership over SSH, matching the remote
              # `openclaw node identity` device key exactly. Reachability alone never approves, so LAN
              # co-tenants fall through to the normal prompt.
              #
              # Without an SSH identity there is no automatic surface approval; the probe is disabled
              # explicitly rather than left to fail and put a node into cooldown. The first surface then
              # needs one `nodes approve` (or a minted setup code) per device - after which reconnects are
              # automatic. The node wrapper is exported as `openclaw` on node hosts so the probe's
              # `openclaw node identity --json` resolves.
              nodes.pairing = {
                autoApproveCidrs = [
                  config.my.topology.subnets.mesh.cidr
                  config.my.topology.subnets."mesh-ipv6".cidr
                ];
              }
              // (
                if hasFleetCredential then
                  {
                    sshVerify = {
                      user = "root";
                      identity = identityFile;
                      cidrs = [
                        config.my.topology.subnets.mesh.cidr
                        config.my.topology.subnets."mesh-ipv6".cidr
                      ];
                    };
                  }
                else
                  { sshVerify = false; }
              );
              controlUi = {
                enabled = true;
                allowedOrigins = [ contract.publications.web.publicUrl ];
              };
            };
          }
          // lib.optionalAttrs instance.apps.enable {
            mcp.apps = {
              enabled = true;
              sandboxPort = instance.apps.port;
              sandboxOrigin = contract.publications.apps.publicUrl;
            };
          }
        );
      };
      archiveDir = "/var/lib/openclaw-backups/${name}";
      archive = pkgs.writeShellScript "${id}-archive" ''
        set -euo pipefail
        umask 077
        staging="$(mktemp -d ${lib.escapeShellArg "${archiveDir}/capture.XXXXXXXX"})"
        trap 'rm -rf -- "$staging"' EXIT
        ${built.launcher}/bin/${id} backup create --verify --output "$staging"
        shopt -s nullglob
        archives=("$staging"/*.tar.gz)
        if [ "''${#archives[@]}" -ne 1 ]; then
          echo "Expected one verified OpenClaw archive in $staging" >&2
          exit 1
        fi
        mv -f -- "''${archives[0]}" ${lib.escapeShellArg "${archiveDir}/latest.tar.gz"}
      '';
    in
    {
      users.groups.${user} = { };
      users.users.${user} = {
        isSystemUser = true;
        group = user;
        home = instance.stateDir;
        shell = pkgs.bashInteractive;
      };
      environment.systemPackages = [
        built.launcher
        built.execute
      ];
      environment.etc = {
        "openclaw/${id}.json".source = built.source;
      }
      // lib.optionalAttrs hasFleetCredential {
        "openclaw/${id}.ssh".text = lib.concatMapStringsSep "\n" (target: ''
          Host ${target} ${config.my.topology.hosts.${target}.wireguardIpv4}
            HostName ${config.my.topology.hosts.${target}.wireguardIpv4}
            User root
            IdentityFile ${identityFile}
            IdentitiesOnly yes
            StrictHostKeyChecking yes
            UserKnownHostsFile /etc/ssh/ssh_known_hosts
        '') instance.fleet.hosts;
      };
      sops.secrets =
        lib.genAttrs (lib.attrValues instance.secrets) (_: { })
        // lib.optionalAttrs (instance.fleet.privateKeySecret != null) {
          # The fleet credential belongs to this gateway's account alone, so each person's gateway
          # reads only its own identity.
          ${instance.fleet.privateKeySecret} = {
            owner = user;
            mode = "0400";
          };
        };
      sops.templates = lib.mapAttrs' (
        variable: secret:
        lib.nameValuePair "${id}-${variable}" {
          owner = user;
          mode = "0400";
          content = config.sops.placeholder.${secret};
          restartUnits = [ "${id}.service" ];
        }
      ) instance.secrets;
      systemd.services = {
        ${id} = {
          description = "Personal OpenClaw gateway (${instance.owner})";
          after = [
            "network-online.target"
            "sops-nix.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [
            built.source
            built.launcher
          ];
          serviceConfig = instance.serviceConfig // {
            User = user;
            Group = user;
            WorkingDirectory = instance.stateDir;
            ExecStart = "${built.launcher}/bin/${id} gateway --port ${toString instance.port}";
            Restart = "on-failure";
            RestartSec = 5;
            UMask = "0077";
          };
        };
      }
      // lib.optionalAttrs instance.publishing.enable {
        "${id}-publishing" = {
          description = "OpenClaw public application router (${instance.owner})";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartTriggers = [ routerConfig ];
          serviceConfig = {
            User = user;
            Group = user;
            RuntimeDirectory = "openclaw-publishing-${name}";
            RuntimeDirectoryMode = "0700";
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${socketDir}";
            ExecStart = "${pkgs.caddy}/bin/caddy run --config ${routerConfig} --adapter caddyfile";
            Restart = "on-failure";
            RestartSec = 5;
            UMask = "0077";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ReadWritePaths = [ "/run/openclaw-publishing-${name}" ];
          };
        };
      };
      systemd.tmpfiles.rules = [
        "d /var/lib/openclaw 0711 root root - -"
        "d /var/lib/openclaw/instances 0711 root root - -"
        "d ${instance.stateDir} 0700 ${user} ${user} - -"
      ]
      ++ lib.optionals instance.backup [
        "d /var/lib/openclaw-backups 0711 root root - -"
        "d ${archiveDir} 0700 ${user} ${user} - -"
      ];
      my.contracts.provides = {
        ${id} = {
          endpoints = {
            web = {
              port = instance.port;
              directAccess = {
                enable = true;
                interface = "wireguard";
                fromHosts = instance.nodeHosts ++ [ config.my.topology.ingressHost ];
              };
            };
          }
          // lib.optionalAttrs instance.apps.enable {
            apps = {
              port = instance.apps.port;
              directAccess = {
                enable = true;
                interface = "wireguard";
                fromHosts = [ config.my.topology.ingressHost ];
              };
            };
          };
          publications = {
            web = {
              endpoint = "web";
              scope = "public";
              auth = "authentik";
              ingressOnly = true;
              accessUsers = [ instance.owner ];
              # These routes authenticate their own short-lived credentials. Native clients must
              # reach them without an interactive SSO redirect.
              unauthenticatedPaths = [
                "/j/*"
                "/__openclaw__/worker"
              ];
              # Native WebSockets carry signed device identity plus bootstrap/device credentials
              # in the OpenClaw handshake, not a browser session. Stripping identity headers on
              # this bypass is essential: the Gateway must authenticate the device itself.
              machineClientsBypassAuth = true;
              # The gateway reads this header as a connection scope cap; it belongs to this
              # publication, not to the shared ingress, so the declaration carries it.
              stripRequestHeaders = [ "X-OpenClaw-Scopes" ];
              inherit (instance) subdomain;
              proxyOptions = "flush_interval -1";
            };
          }
          // lib.optionalAttrs instance.apps.enable {
            apps = {
              endpoint = "apps";
              scope = "public";
              auth = "authentik";
              ingressOnly = true;
              accessUsers = [ instance.owner ];
              stripRequestHeaders = [ "X-OpenClaw-Scopes" ];
              subdomain = instance.apps.subdomain;
            };
          };
          presentation.tiles.web = {
            endpoint = "web";
            show = true;
            displayName = "OpenClaw (${instance.owner})";
            category = "AI & Agents";
            icon = "bot";
          };
          telemetry.probes.gateway = {
            endpoint = "web";
            kind = "tcp";
          };
          storage.stateDirs = [ instance.stateDir ];
          backup = {
            enable = instance.backup;
            paths = [ archiveDir ];
            exclude = [ instance.stateDir ];
            preBackup = "${pkgs.util-linux}/bin/runuser -u ${user} -- ${archive}";
          };
        };
      }
      // lib.optionalAttrs instance.publishing.enable {
        "${id}-publishing" = {
          endpoints.web = {
            port = instance.publishing.port;
            directAccess = {
              enable = true;
              interface = "wireguard";
              fromHosts = [ config.my.topology.ingressHost ];
            };
          };
          publications.web = {
            endpoint = "web";
            scope = "public";
            ingressOnly = true;
            subdomain = "*.${instance.publishing.subdomain}";
            auth = "none";
            publicExempt = "User-published applications are intentionally public, isolated from personal gateway and MCP Apps origins.";
          };
          telemetry.probes.router = {
            endpoint = "web";
            kind = "tcp";
          };
        };
      };
      security.sudo.extraRules = lib.optionals instance.fleet.enable [
        {
          users = [ user ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
      nix.settings.trusted-users = lib.optional instance.fleet.enable user;
      warnings =
        lib.optional
          (
            instance.fleet.enable
            && instance.fleet.hosts != [ ]
            && instance.fleet.privateKeyFile == null
            && instance.fleet.privateKeySecret == null
          )
          "OpenClaw ${name}: local root administration is enabled, but fleet SSH still requires a private/public credential pair.";
    };
  parts = lib.mapAttrsToList make cfg.instances;
  merge = field: lib.mkMerge (map (part: part.${field}) parts);
in
{
  config = lib.mkIf cfg.enable {
    users = merge "users";
    environment = merge "environment";
    sops = merge "sops";
    systemd = merge "systemd";
    my.contracts.provides = lib.mkMerge (map (part: part.my.contracts.provides) parts);
    security = merge "security";
    nix = merge "nix";
    warnings = lib.concatMap (part: part.warnings) parts;
  };
}
