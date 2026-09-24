# features/services/openclaw/node/default.nix
# OpenClaw companion node (role: node) — a peripheral that connects to an OpenClaw gateway
# and exposes a command surface (system.run, system.which, browser proxy, MCP servers, …)
# which the gateway invokes through node.invoke.
#
# Supports running multiple node instances concurrently (e.g. hom-wrk-01 connecting to Philipp's
# gateway, while shared nodes like hom-srv-01 can connect instances to multiple user gateways).
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

  # The command surface and the shared execution baseline. Both live in ../lib so the gateway module
  # consumes the same table and the same package list instead of restating them.
  surface = import ../lib/command-surface.nix { inherit lib; };
  defaultBasePackages = import ../lib/base-packages.nix { inherit pkgs; };

  # `nod` is a flake input, not a nixpkgs package, so it is referenced through the input. It is only
  # put on the PATH of instances that were given a deploy/rebuild power.
  nodPackage = topArgs.inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
        // lib.optionalAttrs inst.workspace.enable {
          worktreeRoot = inst.workspace.root;
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
            default = "openclaw-tunnel";
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
            # Deliberately NOT ~/.ssh/deploy-key: that path belongs to the fleet deploy key, and a
            # rendered tunnel secret living there silently replaces it - after which every deploy
            # loses root access to the whole fleet.
            default = "~/.ssh/node-tunnel-key";
            description = "SSH private key used for the forward; `~` expands to the home of tunnel.serviceUser.";
          };

          privateKeySecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = osConfig.my.features.services.openclaw.node.tunnelPrivateKeySecret;
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

        capabilities = lib.mkOption {
          type = lib.types.listOf (lib.types.enum surface.familyNames);
          default = surface.profiles.node-linux;
          description = ''
            Capability families this instance is expected to serve, from
            features/services/openclaw/lib/command-surface.nix. The node always advertises every
            command it has - the gateway decides what it grants - so this is the declaration the
            fleet consistency check compares the gateway's grant against, and the platform
            assertion checks it against. Narrow it to state intent, not to restrict execution.
          '';
        };

        powers = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "repo.write"
              "fleet.deploy"
              "flow.push"
              "system.rebuild"
            ]
          );
          default = [ ];
          description = ''
            Operator powers of this instance's agent, projected to real grants and nothing more:
              repo.write     - ACL write access to `my.features.services.openclaw.node.repoPath`
              fleet.deploy   - the fleet deploy private key in the instance home (`nod deploy`)
              flow.push      - a GitHub token in the service env, wired as a git credential
              system.rebuild - Nix trusted user plus passwordless `nod`/`nixos-rebuild`
            Empty for every instance that is not its owner; the family's instances carry none.
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

        workspace = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Declare this instance's repository checkout root (OpenClaw's `worktreeRoot`).";
          };

          root = lib.mkOption {
            type = lib.types.str;
            default = "${stateDir}/dev";
            description = ''
              Absolute path under which OpenClaw allocates managed worktrees
              (`<root>/<repo-fingerprint>/<name>`). Created by tmpfiles; `git clone` by hand into
              the state directory is what this replaces - managed worktrees carry their own
              snapshot and cleanup lifecycle, unmanaged checkouts do not.
            '';
          };
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

        # Every instance is its own system user. The shared `openclaw` account made the 0700 state
        # directories meaningless: five instances on one host had the same owner and could read each
        # other's state, credentials and memory. The name is derived, never declared.
        _serviceUser = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = "openclaw-${name}";
        };

        _serviceGroup = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = "openclaw-${name}";
        };
      };
    };

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) cfg.instances;

  # Instances that carry the `system.rebuild` power, projected to the users that may act as a Nix
  # trusted user and invoke the deployer through sudo.
  trustedUsers = lib.mapAttrsToList (_: inst: inst._serviceUser) (
    lib.filterAttrs (_: inst: lib.elem "system.rebuild" inst.powers) enabledInstances
  );
in
{
  options.my.features.services.openclaw.node = {
    enable = lib.mkEnableOption "OpenClaw companion node service";

    # Where the configuration repository lives on a host whose agent was given `repo.write`.
    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Absolute path of the fleet repository the `repo.write` power grants access to.";
    };

    # Credentials the powers project. Secrets, not literals, because a grant is a key.
    deployKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "infra/deploy_key";
      description = "SOPS secret holding the fleet deploy private key (`fleet.deploy`).";
    };

    deployKeySopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ../../../../secrets/deploy-key.yaml;
      description = "SOPS file for the fleet deploy key, deliberately not encrypted to CI.";
    };

    pushTokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "users/${osConfig.my.user.primary}/github_pat";
      description = "SOPS secret holding a GitHub token with write access (`flow.push`).";
    };

    # Node -> gateway loopback-tunnel credential, declared once instead of per host: every
    # host that runs a tunnelled node renders this secret automatically, and the gateway
    # feature authorizes the matching public key on the gateway side only
    # (my.features.services.openclaw.gateway.trustedNodeKeys).
    tunnelPrivateKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "infra/node_tunnel_key";
      description = "SOPS secret holding the private key used by loopback tunnels.";
    };

    tunnelPrivateKeySopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ../../../../secrets/node-tunnel.yaml;
      description = ''
        SOPS file containing the tunnel private key. Kept separate from the main secret store
        so it is never encrypted to the CI age key (see .sops.yaml).
      '';
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
        {
          assertion = lib.all (
            capability:
            surface.supports {
              inherit capability;
              platform = "linux";
            }
          ) inst.capabilities;
          message =
            let
              unsupported = lib.filter (
                capability:
                !surface.supports {
                  inherit capability;
                  platform = "linux";
                }
              ) inst.capabilities;
            in
            "OpenClaw node instance '${name}': capabilities ${lib.concatStringsSep ", " unsupported} are not available on linux (see features/services/openclaw/lib/command-surface.nix).";
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
              sopsFile = osConfig.my.features.services.openclaw.node.tunnelPrivateKeySopsFile;
            };
          })
          (lib.mkIf (lib.elem "fleet.deploy" inst.powers) {
            "${osConfig.my.features.services.openclaw.node.deployKeySecret}" = {
              sopsFile = osConfig.my.features.services.openclaw.node.deployKeySopsFile;
              path = "${inst._stateDir}/.ssh/nixfiles-deploy-key";
              owner = inst._serviceUser;
              group = inst._serviceGroup;
              mode = "0400";
            };
          })
          (lib.mkIf (lib.elem "flow.push" inst.powers) {
            "${osConfig.my.features.services.openclaw.node.pushTokenSecret}" = {
              owner = inst._serviceUser;
              group = inst._serviceGroup;
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
            owner = inst._serviceUser;
            restartUnits = [ "openclaw-node-${name}.service" ];
            content =
              "OPENCLAW_GATEWAY_PASSWORD=${osConfig.sops.placeholder.${inst.passwordSecret}}\n"
              + lib.optionalString (lib.elem "flow.push" inst.powers) ''
                GITHUB_TOKEN=${
                  osConfig.sops.placeholder.${osConfig.my.features.services.openclaw.node.pushTokenSecret}
                }
                GH_TOKEN=${osConfig.sops.placeholder.${osConfig.my.features.services.openclaw.node.pushTokenSecret}}
              ''
              + lib.optionalString (lib.elem "flow.push" inst.powers) ''
                GIT_CONFIG_COUNT=1
                GIT_CONFIG_KEY_0=credential.https://github.com.helper
                GIT_CONFIG_VALUE_0=!${pkgs.gh}/bin/gh auth git-credential
              '';
          };
        }
      ) (lib.attrNames enabledInstances)
    );

    users.groups = lib.mapAttrs' (_: inst: lib.nameValuePair inst._serviceGroup { }) enabledInstances;

    users.users = lib.mapAttrs' (
      _: inst:
      lib.nameValuePair inst._serviceUser {
        isSystemUser = true;
        group = inst._serviceGroup;
        home = inst._stateDir;
        createHome = false;
        shell = pkgs.bashInteractive;
      }
    ) enabledInstances;

    # Only instances carrying the `system.rebuild` power are Nix trusted users or may invoke the
    # deployer through sudo. The blanket grant to the shared account is gone.
    nix.settings.trusted-users = trustedUsers;

    security.sudo.extraRules = lib.optional (trustedUsers != [ ]) {
      users = trustedUsers;
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
    };

    # `repo.write`: an access ACL for existing files and a default ACL so new files (git checkouts,
    # editor writes) inherit it. The ACL is the grant; the path comes from `repoPath`.
    # File-level projections of the powers. `repo.write` grants the ACL; every deploy/rebuild power
    # also needs a `safe.directory` entry in the *instance's* gitconfig, because Nix's libgit2 - unlike
    # the git CLI - does not read the GIT_CONFIG_* environment and refuses a repository it does not own
    # (`repository path '/etc/nixos' is not owned by current user`).
    system.activationScripts = lib.mapAttrs' (
      name: inst:
      let
        repoPath = osConfig.my.features.services.openclaw.node.repoPath;
        writesRepoAcl = lib.elem "repo.write" inst.powers;
        needsGitConfig = lib.any (power: lib.elem power inst.powers) [
          "repo.write"
          "fleet.deploy"
          "system.rebuild"
        ];
      in
      lib.nameValuePair "openclaw-node-${name}-powers" (
        lib.mkIf (writesRepoAcl || needsGitConfig) (
          lib.optionalString writesRepoAcl ''
            if [ -d ${repoPath} ]; then
              ${pkgs.acl}/bin/setfacl -R -m u:${inst._serviceUser}:rwX ${repoPath}
              ${pkgs.findutils}/bin/find ${repoPath} -type d -exec ${pkgs.acl}/bin/setfacl -m d:u:${inst._serviceUser}:rwX {} +
            fi
          ''
          + lib.optionalString needsGitConfig ''
            printf '[safe]\n\tdirectory = %s\n' ${repoPath} > ${inst._stateDir}/.gitconfig
            chown ${inst._serviceUser}:${inst._serviceGroup} ${inst._stateDir}/.gitconfig
            chmod 0600 ${inst._stateDir}/.gitconfig
          ''
        )
      )
    ) enabledInstances;

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
      # Traversable containers, owned by root: an instance user may walk into the tree but not
      # list it, and each instance directory below carries the instance's own owner and mode.
      "d /var/lib/openclaw 0711 root root - -"
      "d /var/lib/openclaw/node-instances 0711 root root - -"
      "d /etc/openclaw 0755 root root - -"
      "d /etc/openclaw/node-instances 0755 root root - -"
    ]
    ++ lib.concatMap (
      name:
      let
        inst = enabledInstances.${name};
      in
      # Z (capital): recursive ownership repair, so state written under the old shared account keeps
      # working after the instance got its own user. Lowercase z only adjusted the path itself.
      [
        "d ${inst._stateDir} 0700 ${inst._serviceUser} ${inst._serviceGroup} - -"
        "Z ${inst._stateDir} - ${inst._serviceUser} ${inst._serviceGroup} - -"
      ]
      ++ lib.optional inst.workspace.enable (
        "d ${inst.workspace.root} 0700 ${inst._serviceUser} ${inst._serviceGroup} - -"
      )
      ++ lib.optional (lib.elem "fleet.deploy" inst.powers) "d ${inst._stateDir}/.ssh 0700 ${inst._serviceUser} ${inst._serviceGroup} - -"
    ) (lib.attrNames enabledInstances)
    # sops-nix can only render the tunnel key if its parent directory exists.
    ++ lib.unique (
      map
        (
          name:
          let
            inst = enabledInstances.${name};
          in
          "d ${builtins.dirOf inst._identityFile} 0700 ${inst.tunnel.serviceUser} users - -"
        )
        (
          builtins.filter (name: enabledInstances.${name}.tunnel.privateKeySecret != null) (
            lib.attrNames enabledInstances
          )
        )
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
            after = [ "network-online.target" ];
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
              after = [ "network-online.target" ] ++ lib.optional inst._useTunnel "${tunnelServiceName}.service";
              wants = [ "network-online.target" ];
              requires = lib.optional inst._useTunnel "${tunnelServiceName}.service";

              # `environment` (not `serviceConfig.Environment`) is the systemd unit option that
              # quotes values, so an author name with a space survives instead of being dropped
              # with "Invalid environment assignment". The gateway unit has always done this; the
              # node unit kept a raw list and lost GIT_AUTHOR_* on every start.
              environment = {
                HOME = inst._stateDir;
                OPENCLAW_STATE_DIR = inst._stateDir;
              }
              // lib.optionalAttrs (inst._mergedConfig != { }) {
                OPENCLAW_CONFIG_PATH = inst._configPath;
              }
              // lib.optionalAttrs (inst.gitAuthor.name != null) {
                GIT_AUTHOR_NAME = inst.gitAuthor.name;
                GIT_COMMITTER_NAME = inst.gitAuthor.name;
              }
              // lib.optionalAttrs (inst.gitAuthor.email != null) {
                GIT_AUTHOR_EMAIL = inst.gitAuthor.email;
                GIT_COMMITTER_EMAIL = inst.gitAuthor.email;
              };

              serviceConfig = {
                User = inst._serviceUser;
                Group = inst._serviceGroup;
                WorkingDirectory = inst._stateDir;
                StateDirectory = "openclaw/node-instances/${name}";
                StateDirectoryMode = "0700";
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
              ++ lib.optional (lib.any (power: lib.elem power inst.powers) [
                "fleet.deploy"
                "system.rebuild"
              ]) nodPackage
              ++ lib.optional inst.browserProxy.enable inst.browserProxy.package;
            };
          }
        ]
      ) (lib.attrNames enabledInstances)
    );
  };
}
