# features/services/openclaw/node/default.nix
# OpenClaw companion node (role: node) — a peripheral that connects to an OpenClaw gateway
# and exposes a command surface (system.run, system.which, browser proxy, MCP servers, …)
# which the gateway invokes through node.invoke.
#
# Supports running multiple node instances concurrently (e.g. jello connecting to Philipp's
# gateway, while shared nodes like strummer can connect instances to multiple user gateways).
#
# Transports:
#   loopback-tunnel   (Default) The node connects to the gateway via an SSH -L forward
#                     to 127.0.0.1 and authenticates with the shared gateway password.
#                     This is mandatory when the gateway runs with `auth.mode = "trusted-proxy"`,
#                     as OpenClaw's security policy requires clean loopback for password auth.
#
#   direct            The node dials the gateway directly (e.g. over Tailscale or token auth).
{
  lib,
  pkgs,
  ...
}@topArgs:
let
  osConfig = topArgs.config;
  cfg = osConfig.my.features.services.openclaw.node;

  # Standard baseline toolchain available to OpenClaw execution environments
  defaultBasePackages = [
    pkgs.nix
    pkgs.git
    pkgs.gh
    pkgs.ripgrep
    pkgs.ripgrep-all
    pkgs.fd
    pkgs.procps
    pkgs.curl
    pkgs.gnutar
    pkgs.gzip
    pkgs.zip
    pkgs.unzip
    pkgs.jq
    pkgs.yq-go
    pkgs.sqlite
    pkgs.poppler-utils
    pkgs.imagemagick
    pkgs.pandoc
    pkgs.ast-grep
    pkgs.universal-ctags
    pkgs.tokei
    pkgs.lsof
    pkgs.moreutils
    pkgs.nvd
    pkgs.nix-diff
  ];

  # Submodule schema for a single node instance
  instanceSubmodule =
    { name, config, ... }:
    let
      inst = config;

      useTunnel = inst.transport == "loopback-tunnel";

      dial = {
        host = if useTunnel then "127.0.0.1" else inst.gateway.host;
        port = if useTunnel then inst.tunnel.localPort else inst.gateway.port;
        tls = !useTunnel && inst.gateway.tls;
      };

      hasPassword = inst.passwordSecret != null;

      stateDir = "/var/lib/openclaw/node-instances/${name}";
      configPath = "/etc/openclaw/node-instances/${name}.json";

      serviceHome = osConfig.users.users.${inst.tunnel.serviceUser}.home;
      identityFile = lib.replaceStrings [ "~/" ] [ "${serviceHome}/" ] inst.tunnel.identityFile;

      mergedNodeHost = lib.recursiveUpdate (
        (lib.optionalAttrs inst.sessionHosting.enable {
          workerRuns = {
            enabled = true;
          }
          // lib.optionalAttrs (inst.sessionHosting.capacity != null) {
            capacity = inst.sessionHosting.capacity;
          };
        })
        // (lib.optionalAttrs inst.browserProxy.enable {
          browserProxy = {
            enabled = true;
          }
          // lib.optionalAttrs (inst.browserProxy.allowProfiles != [ ]) {
            allowProfiles = inst.browserProxy.allowProfiles;
          };
        })
      ) inst.nodeHost;

      browserExecutable =
        if inst.browser.executablePath != null then
          inst.browser.executablePath
        else if inst.browserProxy.enable then
          "${inst.browserProxy.package}/bin/chromium"
        else
          null;

      mergedConfig = lib.recursiveUpdate (
        lib.optionalAttrs (mergedNodeHost != { }) {
          nodeHost = mergedNodeHost;
        }
        //
          lib.optionalAttrs
            (browserExecutable != null || inst.browser.headless != null || inst.browser.noSandbox != null)
            {
              browser =
                lib.optionalAttrs (browserExecutable != null) {
                  executablePath = browserExecutable;
                }
                // lib.optionalAttrs (inst.browser.headless != null) {
                  headless = inst.browser.headless;
                }
                // lib.optionalAttrs (inst.browser.noSandbox != null) {
                  noSandbox = inst.browser.noSandbox;
                };
            }
      ) inst.settings;

      configFile = pkgs.writeText "openclaw-node-${name}.json" (builtins.toJSON mergedConfig);
    in
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable this node instance.";
        };

        gateway = {
          host = lib.mkOption {
            type = lib.types.str;
            example = "100.126.5.72";
            description = "Reachable gateway address: Tailscale IP, MagicDNS hostname or public host name.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 18789;
            description = "Gateway port. Defaults to 18789.";
          };

          tls = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether a direct connection dials with TLS. Default is false for plain ws://
              gateway addresses (Tailscale, loopback, private IP literal, .local). Set true
              when connecting over a public TLS reverse-proxy (port 443).
            '';
          };
        };

        transport = lib.mkOption {
          type = lib.types.enum [
            "loopback-tunnel"
            "direct"
          ];
          default = "loopback-tunnel";
          description = ''
            loopback-tunnel: (Default) The node tunnels to the gateway over SSH -L and dials
                            clean 127.0.0.1 with the shared gateway password.
            direct: node dials the gateway directly (e.g. over Tailscale or token auth).
          '';
        };

        sessionHosting = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable OpenClaw worker session hosting on this node instance.";
          };

          capacity = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Worker slot capacity limit. Null defaults to one slot per available CPU core.";
          };
        };

        tunnel = {
          localPort = lib.mkOption {
            type = lib.types.port;
            default = 18790;
            description = "Local loopback port the node dials while the tunnel is active.";
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "root";
            description = "SSH user on the gateway host.";
          };

          serviceUser = lib.mkOption {
            type = lib.types.str;
            default = osConfig.my.user.primary;
            description = ''
              Local user the SSH forward runs as, and whose known_hosts is used. Defaults to
              the primary user because the key that authorizes root on the gateway host is
              that user's deploy key — the same one `nod` and deploy-rs use.
            '';
          };

          identityFile = lib.mkOption {
            type = lib.types.str;
            default = "~/.ssh/deploy-key";
            description = "SSH private key used for the forward; `~` expands to the home of tunnel.serviceUser.";
          };

          privateKeySecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "openclaw_node_ssh_key";
            description = ''
              SOPS secret holding the SSH private key for the forward. When set, it is
              rendered to identityFile with mode 0400.
            '';
          };

          hostKeyPolicy = lib.mkOption {
            type = lib.types.enum [
              "accept-new"
              "strict"
            ];
            default = "accept-new";
            description = "accept-new trusts the gateway host key on first use (TOFU); strict requires a pre-seeded known_hosts entry.";
          };
        };

        passwordSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "ai/openclaw/gateway_password";
          example = "ai/openclaw/gateway_password";
          description = "Optional SOPS secret rendered into OPENCLAW_GATEWAY_PASSWORD.";
        };

        displayName = lib.mkOption {
          type = lib.types.str;
          default = osConfig.networking.hostName;
          description = "Name the node advertises to the gateway.";
        };

        commands = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = ''
            Exact command allowlist to advertise instead of the full default surface
            (system.run, system.which, browser proxy, plugins, MCP).
          '';
        };

        nodeHost = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Node-side openclaw.json settings (nodeHost.*).";
        };

        gitAuthor = {
          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = osConfig.my.user.fullName;
            description = "Git author and committer name for workspace sync and commits made by agent tools.";
          };

          email = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = osConfig.my.user.email;
            description = "Git author and committer email for workspace sync and commits made by agent tools.";
          };
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = defaultBasePackages;
          description = "Packages added to the PATH of commands executed on this node instance.";
        };

        browser = {
          executablePath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Explicit path to Chromium browser binary on this node. Defaults to browserProxy.package/bin/chromium if null and browserProxy.enable is true.";
          };

          headless = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Explicit headless override for browser sessions managed by this node.";
          };

          noSandbox = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Disable Chromium sandbox flags on this node if needed.";
          };
        };

        browserProxy = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Expose local browser control to the paired gateway via node routing.";
          };

          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.chromium;
            description = "Chromium package provided to the node host environment when browserProxy is enabled.";
          };

          allowProfiles = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Optional allowlist of browser profile names exposed through node proxy routing. Empty allows all.";
          };
        };

        settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Arbitrary openclaw.json overrides merged into this node instance configuration.";
        };

        # Computed internal helpers
        _useTunnel = lib.mkOption {
          type = lib.types.bool;
          internal = true;
          default = useTunnel;
        };

        _dial = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          default = dial;
        };

        _hasPassword = lib.mkOption {
          type = lib.types.bool;
          internal = true;
          default = hasPassword;
        };

        _stateDir = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = stateDir;
        };

        _configPath = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = configPath;
        };

        _identityFile = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = identityFile;
        };

        _serviceHome = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = serviceHome;
        };

        _mergedNodeHost = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          default = mergedNodeHost;
        };

        _mergedConfig = lib.mkOption {
          type = lib.types.attrs;
          internal = true;
          default = mergedConfig;
        };

        _configFile = lib.mkOption {
          type = lib.types.package;
          internal = true;
          default = configFile;
        };
      };
    };

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) cfg.instances;
in
{
  options.my.features.services.openclaw.node = {
    enable = lib.mkEnableOption "OpenClaw companion node service";

    rebuild = {
      enable = lib.mkEnableOption "allow openclaw to test and switch system configurations (nix trusted-user, sudoers for nod and nixos-rebuild)";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceSubmodule);
      default = { };
      description = "Declared OpenClaw companion node instances.";
    };
  };

  config = lib.mkIf (cfg.enable && enabledInstances != { }) {
    assertions = lib.concatMap (
      name:
      let
        inst = enabledInstances.${name};
      in
      [
        {
          assertion = !inst._useTunnel || inst._hasPassword;
          message = ''
            OpenClaw node instance '${name}' with transport = "loopback-tunnel" requires
            passwordSecret: with gateway.auth.mode = "trusted-proxy" the shared password is
            the only credential accepted for a clean loopback caller.
          '';
        }
        {
          assertion = !inst._useTunnel || inst.gateway.host != "127.0.0.1";
          message = "OpenClaw node instance '${name}': gateway.host must be the gateway's reachable address, not the local loopback address.";
        }
        {
          assertion = inst._useTunnel || inst.gateway.host != "127.0.0.1";
          message = "OpenClaw node instance '${name}': transport = \"direct\" needs a real gateway host, otherwise the node only reaches itself.";
        }
      ]
    ) (lib.attrNames enabledInstances);

    sops.secrets = lib.mkMerge (
      lib.concatMap (
        name:
        let
          inst = enabledInstances.${name};
        in
        [
          (lib.mkIf inst._hasPassword {
            "${inst.passwordSecret}" = { };
          })
          (lib.mkIf (inst._useTunnel && inst.tunnel.privateKeySecret != null) {
            "${inst.tunnel.privateKeySecret}" = {
              path = inst._identityFile;
              owner = inst.tunnel.serviceUser;
              mode = "0400";
            };
          })
        ]
      ) (lib.attrNames enabledInstances)
    );

    sops.templates = lib.listToAttrs (
      lib.concatMap (
        name:
        let
          inst = enabledInstances.${name};
        in
        lib.optional inst._hasPassword {
          name = "openclaw_node_${name}_env";
          value = {
            owner = "openclaw";
            restartUnits = [ "openclaw-node-${name}.service" ];
            content = "OPENCLAW_GATEWAY_PASSWORD=${osConfig.sops.placeholder.${inst.passwordSecret}}\n";
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    users.groups.openclaw = { };

    users.users.openclaw = {
      isSystemUser = true;
      group = "openclaw";
      home = "/var/lib/openclaw";
      createHome = true;
      shell = pkgs.bashInteractive;
    };

    nix.settings.trusted-users = lib.mkIf cfg.rebuild.enable [ "openclaw" ];

    security.sudo.extraRules = lib.mkIf cfg.rebuild.enable [
      {
        users = [ "openclaw" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/nod switch *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nod test *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nod check *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nixos-rebuild switch *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nixos-rebuild test *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/nixos-rebuild dry-run *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    environment.etc = lib.listToAttrs (
      lib.concatMap (
        name:
        let
          inst = enabledInstances.${name};
        in
        lib.optional (inst._mergedConfig != { }) {
          name = "openclaw/node-instances/${name}.json";
          value = {
            mode = "0644";
            source = inst._configFile;
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    systemd.tmpfiles.rules = [
      "d /var/lib/openclaw 0750 openclaw openclaw - -"
      "d /var/lib/openclaw/node-instances 0750 openclaw openclaw - -"
      "d /etc/openclaw 0755 root root - -"
      "d /etc/openclaw/node-instances 0755 root root - -"
    ]
    ++ map (name: "d ${enabledInstances.${name}._stateDir} 0700 openclaw openclaw - -") (
      lib.attrNames enabledInstances
    );

    systemd.services = lib.listToAttrs (
      lib.concatMap (
        name:
        let
          inst = enabledInstances.${name};
          tunnelServiceName = "openclaw-node-tunnel-${name}";
          nodeServiceName = "openclaw-node-${name}";
        in
        lib.optional inst._useTunnel {
          name = tunnelServiceName;
          value = {
            description = "OpenClaw gateway loopback tunnel (${name})";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "tailscaled.service"
            ];
            wants = [ "network-online.target" ];

            serviceConfig = {
              User = inst.tunnel.serviceUser;
              Environment = [ "HOME=${inst._serviceHome}" ];
              ExecStart = lib.concatStringsSep " " [
                "${pkgs.openssh}/bin/ssh -N"
                "-o BatchMode=yes"
                "-o ExitOnForwardFailure=yes"
                "-o ConnectTimeout=10"
                "-o ServerAliveInterval=15"
                "-o ServerAliveCountMax=3"
                "-o StrictHostKeyChecking=${inst.tunnel.hostKeyPolicy}"
                "-i ${inst._identityFile}"
                "-L ${toString inst.tunnel.localPort}:127.0.0.1:${toString inst.gateway.port}"
                "${inst.tunnel.user}@${inst.gateway.host}"
              ];
              Restart = "always";
              RestartSec = 5;
            };
          };
        }
        ++ [
          {
            name = nodeServiceName;
            value = {
              description = "OpenClaw companion node (${name})";
              wantedBy = [ "multi-user.target" ];
              restartTriggers = lib.optional (inst._mergedConfig != { }) inst._configFile;
              after = [
                "network-online.target"
                "tailscaled.service"
              ]
              ++ lib.optional inst._useTunnel "${tunnelServiceName}.service";
              wants = [ "network-online.target" ];
              requires = lib.optional inst._useTunnel "${tunnelServiceName}.service";

              serviceConfig = {
                User = "openclaw";
                Group = "openclaw";
                WorkingDirectory = inst._stateDir;
                StateDirectory = "openclaw/node-instances/${name}";
                StateDirectoryMode = "0700";
                Environment = [
                  "HOME=${inst._stateDir}"
                  "OPENCLAW_STATE_DIR=${inst._stateDir}"
                ]
                ++ lib.optional (inst._mergedConfig != { }) "OPENCLAW_CONFIG_PATH=${inst._configPath}"
                ++ lib.optional (inst.gitAuthor.name != null) "GIT_AUTHOR_NAME=${inst.gitAuthor.name}"
                ++ lib.optional (inst.gitAuthor.name != null) "GIT_COMMITTER_NAME=${inst.gitAuthor.name}"
                ++ lib.optional (inst.gitAuthor.email != null) "GIT_AUTHOR_EMAIL=${inst.gitAuthor.email}"
                ++ lib.optional (inst.gitAuthor.email != null) "GIT_COMMITTER_EMAIL=${inst.gitAuthor.email}";
                EnvironmentFile =
                  lib.optional inst._hasPassword
                    osConfig.sops.templates."openclaw_node_${name}_env".path;
                ExecStart = lib.concatStringsSep " " (
                  [
                    "${pkgs.openclaw}/bin/openclaw node run"
                    "--host ${inst._dial.host}"
                    "--port ${toString inst._dial.port}"
                    (if inst._dial.tls then "--tls" else "--no-tls")
                    "--display-name ${inst.displayName}"
                  ]
                  ++ lib.optional (inst.commands != null) "--commands ${lib.concatStringsSep "," inst.commands}"
                );
                Restart = "always";
                RestartSec = 5;
              };

              path = [
                pkgs.bash
                pkgs.coreutils
              ]
              ++ inst.extraPackages
              ++ lib.optional inst.browserProxy.enable inst.browserProxy.package;
            };
          }
        ]
      ) (lib.attrNames enabledInstances)
    );
  };
}
