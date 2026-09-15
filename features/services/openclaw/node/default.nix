# features/services/openclaw/node/default.nix
# OpenClaw companion node (role: node) — a peripheral that connects to a gateway and exposes
# a command surface (system.run, system.which, browser proxy, MCP servers, …) which the
# gateway invokes through node.invoke. A node runs no gateway, owns no channels and holds
# no operator credentials: after pairing it authenticates with a `role: "node"` scoped
# device token.
#
# Transports:
#   loopback-tunnel   (Default) The node connects to the gateway via an SSH -L forward
#                     to 127.0.0.1 and authenticates with the shared gateway password.
#                     This is mandatory when the gateway runs with `auth.mode = "trusted-proxy"`,
#                     as OpenClaw's security policy requires clean loopback for password auth.
#
#   direct            The node dials the gateway directly (e.g. over Tailscale or token auth).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.openclaw.node;

  useTunnel = cfg.transport == "loopback-tunnel";

  # The node talks plaintext over private/tailnet or SSH tunnel; direct over public routes follows gateway.tls.
  dial = {
    host = if useTunnel then "127.0.0.1" else cfg.gateway.host;
    port = if useTunnel then cfg.tunnel.localPort else cfg.gateway.port;
    tls = !useTunnel && cfg.gateway.tls;
  };

  hasPassword = cfg.passwordSecret != null;

  # Fixed, not configurable: it must match systemd's StateDirectory= so that the
  # directory is created (and owned by User=) before ExecStart runs.
  stateDir = "/var/lib/openclaw";

  serviceHome = config.users.users.${cfg.tunnel.serviceUser}.home;

  # `~` in identityFile resolves against the service user's home, not root's.
  identityFile = lib.replaceStrings [ "~/" ] [ "${serviceHome}/" ] cfg.tunnel.identityFile;

  mergedNodeHost = lib.recursiveUpdate (lib.optionalAttrs cfg.sessionHosting.enable {
    workerRuns = {
      enabled = true;
    }
    // lib.optionalAttrs (cfg.sessionHosting.capacity != null) {
      capacity = cfg.sessionHosting.capacity;
    };
  }) cfg.nodeHost;
in
{
  options.my.features.services.openclaw.node = {
    enable = lib.mkEnableOption "OpenClaw companion node (role: node)";

    rebuild = {
      enable = lib.mkEnableOption "allow openclaw to test and switch system configurations (nix trusted-user, sudoers for nod and nixos-rebuild)";
    };

    gateway = {
      host = lib.mkOption {
        type = lib.types.str;
        example = "100.126.5.72";
        description = ''
          Reachable gateway address: Tailscale IP, MagicDNS hostname or public host name.
          Deliberately has no default — this module must stay agnostic of network topology.
        '';
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
                        clean 127.0.0.1 with the shared gateway password. This is required
                        when the gateway runs in trusted-proxy auth mode because OpenClaw
                        requires clean loopback for password-authenticated machine connections.
        direct: node dials the gateway directly (e.g. over Tailscale or token auth).
      '';
    };

    sessionHosting = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable OpenClaw worker session hosting on this node (nodeHost.workerRuns.enabled = true).
          Allows the gateway to dispatch worker sessions and runs directly to this machine.
        '';
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
        default = config.my.user.primary;
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
          rendered to identityFile with mode 0400, making the tunnel fully declarative.
          When unset, the file has to exist on the host already.
        '';
      };

      hostKeyPolicy = lib.mkOption {
        type = lib.types.enum [
          "accept-new"
          "strict"
        ];
        default = "accept-new";
        description = ''
          accept-new trusts the gateway host key on first use (TOFU); strict requires a
          pre-seeded known_hosts entry.
        '';
      };
    };

    passwordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "openclaw_gateway_password";
      description = ''
        Optional SOPS secret rendered into OPENCLAW_GATEWAY_PASSWORD. Only needed for
        `transport = "loopback-tunnel"` or password-authenticated direct connections.
      '';
    };

    displayName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Name the node advertises to the gateway.";
    };

    commands = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = ''
        Exact command allowlist to advertise instead of the full default surface
        (system.run, system.which, browser proxy, plugins, MCP). Leaving this unset
        advertises everything the node host supports.
      '';
    };

    nodeHost = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        browserProxy.enabled = false;
        mcp.servers.example.command = "example-mcp";
      };
      description = ''
        Node-side openclaw.json settings (nodeHost.*), written to /etc/openclaw/node.json.
        Use this for browser proxy, MCP servers and skills hosted on the node.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        pkgs.nix
        pkgs.git
        pkgs.ripgrep
        pkgs.fd
        pkgs.procps
      ];
      description = ''
        Packages added to the PATH of commands executed on this node. Defaults to nix, git,
        ripgrep and fd so the agent can build and inspect repositories on the node;
        set to [ ] to run a restricted node.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !useTunnel || hasPassword;
        message = ''
          my.features.services.openclaw.node with transport = "loopback-tunnel" requires
          passwordSecret: with gateway.auth.mode = "trusted-proxy" the shared password is
          the only credential accepted for a clean loopback caller.
        '';
      }
      {
        assertion = !useTunnel || cfg.gateway.host != "127.0.0.1";
        message = "gateway.host must be the gateway's reachable address, not the local loopback address.";
      }
      {
        assertion = useTunnel || cfg.gateway.host != "127.0.0.1";
        message = ''transport = "direct" needs a real gateway host, otherwise the node only reaches itself.'';
      }
    ];

    sops.secrets = lib.mkMerge [
      (lib.mkIf hasPassword {
        "${cfg.passwordSecret}" = { };
      })
      (lib.mkIf (useTunnel && cfg.tunnel.privateKeySecret != null) {
        "${cfg.tunnel.privateKeySecret}" = {
          path = identityFile;
          owner = cfg.tunnel.serviceUser;
          mode = "0400";
        };
      })
    ];

    sops.templates."openclaw-node_env" = lib.mkIf hasPassword {
      owner = "openclaw";
      restartUnits = [ "openclaw-node.service" ];
      content = "OPENCLAW_GATEWAY_PASSWORD=${config.sops.placeholder.${cfg.passwordSecret}}\n";
    };

    users.groups.openclaw = { };

    users.users.openclaw = {
      isSystemUser = true;
      group = "openclaw";
      home = stateDir;
      # The directory itself is owned by StateDirectory= below; /var/lib paths are not
      # created by createHome for system users.
      createHome = false;
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

    environment.etc = lib.mkIf (mergedNodeHost != { }) {
      "openclaw/node.json".source = pkgs.writeText "openclaw-node.json" (
        builtins.toJSON { nodeHost = mergedNodeHost; }
      );
    };

    systemd.tmpfiles.rules = [
      # Repair ownership on activation
      "Z ${stateDir} 0700 openclaw openclaw - -"
    ];

    systemd.services.openclaw-node-tunnel = lib.mkIf useTunnel {
      description = "OpenClaw gateway loopback tunnel";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        User = cfg.tunnel.serviceUser;
        Environment = [ "HOME=${serviceHome}" ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.openssh}/bin/ssh -N"
          "-o BatchMode=yes"
          "-o ExitOnForwardFailure=yes"
          "-o ConnectTimeout=10"
          "-o ServerAliveInterval=15"
          "-o ServerAliveCountMax=3"
          "-o StrictHostKeyChecking=${cfg.tunnel.hostKeyPolicy}"
          "-i ${identityFile}"
          "-L ${toString cfg.tunnel.localPort}:127.0.0.1:${toString cfg.gateway.port}"
          "${cfg.tunnel.user}@${cfg.gateway.host}"
        ];
        Restart = "always";
        RestartSec = 5;
      };
    };

    systemd.services.openclaw-node = {
      description = "OpenClaw companion node";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ]
      ++ lib.optional useTunnel "openclaw-node-tunnel.service";
      wants = [ "network-online.target" ];
      requires = lib.optional useTunnel "openclaw-node-tunnel.service";

      serviceConfig = {
        User = "openclaw";
        Group = "openclaw";
        WorkingDirectory = stateDir;
        StateDirectory = "openclaw";
        StateDirectoryMode = "0700";
        Environment = [
          "HOME=${stateDir}"
          "OPENCLAW_STATE_DIR=${stateDir}"
        ]
        ++ lib.optional (mergedNodeHost != { }) "OPENCLAW_CONFIG_PATH=/etc/openclaw/node.json";
        EnvironmentFile = lib.optional hasPassword config.sops.templates."openclaw-node_env".path;
        ExecStart = lib.concatStringsSep " " (
          [
            "${pkgs.openclaw}/bin/openclaw node run"
            "--host ${dial.host}"
            "--port ${toString dial.port}"
            (if dial.tls then "--tls" else "--no-tls")
            "--display-name ${cfg.displayName}"
          ]
          ++ lib.optional (cfg.commands != null) "--commands ${lib.concatStringsSep "," cfg.commands}"
        );
        Restart = "always";
        RestartSec = 5;
      };

      path = [
        pkgs.bash
        pkgs.coreutils
      ]
      ++ cfg.extraPackages;
    };
  };
}
