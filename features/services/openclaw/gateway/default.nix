# features/services/openclaw/gateway/default.nix
# OpenClaw gateway (role: gateway) — the single trust domain that owns sessions, channels,
# models and pairing state. Runs as a systemd system service via the upstream NixOS module
# (services.openclaw-gateway), which creates and owns the dedicated `openclaw` user and
# keeps config in /etc/openclaw and runtime state in /var/lib/openclaw.
#
# This module deliberately stays agnostic: no domain, no host name and no model catalogue.
# The public URL is derived from the central endpoint registry, provider catalogues and
# model policy belong in the host configuration (see `settings`).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.openclaw.gateway;

  # SSOT for the public URL: the endpoint registry resolves subdomain + caddy.baseDomain.
  publicUrl = config.my.endpoints.openclaw.publicUrl;

  # node/worker clients and the Gateway WS use wss://; browsers use the https:// origin.
  remoteUrl = lib.replaceStrings [ "https://" ] [ "wss://" ] publicUrl;

  secretEnv =
    name: secretName:
    lib.optionalString (secretName != null) "${name}=${config.sops.placeholder.${secretName}}";

  secretEnvLines = lib.filter (line: line != "") [
    (secretEnv "DEEPSEEK_API_KEY" cfg.secrets.deepseek)
    (secretEnv "OPENAI_API_KEY" cfg.secrets.openai)
    (secretEnv "OPENCLAW_GATEWAY_PASSWORD" cfg.secrets.password)
    (secretEnv "GITHUB_TOKEN" cfg.secrets.github)
    (secretEnv "GH_TOKEN" cfg.secrets.github)
  ];

  secretNames = lib.filter (name: name != null) [
    cfg.secrets.deepseek
    cfg.secrets.openai
    cfg.secrets.password
    cfg.secrets.github
  ];

  # Deliberately derived from the option values, not from `config.sops.placeholder`:
  # sops-nix only defines `sops.placeholder` when `sops.templates != {}`, so using a
  # placeholder inside this condition would be an infinite recursion.
  hasSecrets = secretNames != [ ];

  # Parse, don't validate: unknown plugin ids are rejected instead of producing a
  # derivation that fails deep inside the build.
  unknownPlugins = lib.filter (
    id: !(builtins.hasAttr id pkgs.openclawRuntimePlugins)
  ) cfg.runtimePlugins;

  pluginConfig = lib.optionalAttrs (cfg.runtimePlugins != [ ]) {
    plugins = {
      load.paths = map (id: "${pkgs.openclawRuntimePlugins.${id}}") cfg.runtimePlugins;
      entries = lib.genAttrs cfg.runtimePlugins (_: {
        enabled = true;
      });
    };
  };
in
{
  options.my.features.services.openclaw.gateway = {
    enable = lib.mkEnableOption "OpenClaw gateway (role: gateway)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Internal port the gateway listens on (Caddy proxies to it on loopback).";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ai";
      description = "Subdomain of the gateway below caddy.baseDomain, e.g. ai.<baseDomain>.";
    };

    auth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Protect the browser-facing Control UI with Authentik forward-auth.";
    };

    adminUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Authentik identities (email) that receive an `operator.admin` session grant.
        Note: minting node setup links ("Connect machine") and approving `role: node`
        devices also requires `operator.admin`, so every user who should couple their
        own node from the Control UI has to be listed here.
      '';
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "deepseek/deepseek-flash";
      description = "Default agent model reference (must exist in the configured provider catalogue).";
    };

    memorySearch = lib.mkOption {
      type = lib.types.enum [
        "openai"
        "local"
      ];
      default = "openai";
      description = "Embedding provider for memory search.";
    };

    runtimePlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "deepseek" ];
      description = ''
        OpenClaw runtime plugin ids from pkgs.openclawRuntimePlugins. The module wires
        plugins.load.paths and plugins.entries.<id>.enabled, which is exactly what the
        upstream Home Manager module generates for `runtimePlugins`.
      '';
    };

    controlUiExtraOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional allowed origins for the Control UI beyond the public URL. Add the
        tailnet origin here if the UI must be reachable without going through Caddy.
      '';
    };

    autoApproveCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = config.my.features.system.networking.topology.trustedSubnets or [ ];
      example = [ "100.64.0.0/10" ];
      description = ''
        CIDR ranges / IPs from which first-time node-role pairing requests are
        automatically and silently approved (gateway.nodes.pairing.autoApproveCidrs).
        Defaults to the trusted network topology subnets (Tailscale CGNAT + LAN).
      '';
    };

    openTailscaleFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the gateway port on the Tailscale interface for direct node connections.";
    };

    gitAuthor = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.my.user.fullName;
        description = "Git author and committer name for workspace sync and commits made by agent tools.";
      };

      email = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.my.user.email;
        description = "Git author and committer email for workspace sync and commits made by agent tools.";
      };
    };

    secrets = {
      deepseek = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "pi/deepseek";
        description = "SOPS secret rendered into DEEPSEEK_API_KEY.";
      };

      openai = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "openai_api_key";
        description = "SOPS secret rendered into OPENAI_API_KEY (memory search).";
      };

      password = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "openclaw_gateway_password";
        description = ''
          SOPS secret rendered into OPENCLAW_GATEWAY_PASSWORD. Required for nodes that
          reach the gateway over a real loopback transport (`transport = "loopback-tunnel"`),
          because `auth.mode = "trusted-proxy"` only accepts the password for
          "clean loopback/direct callers".
        '';
      };

      github = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "github_pat_philipp";
        description = ''
          SOPS secret rendered into GITHUB_TOKEN and GH_TOKEN for the gateway process.
          Also sets gateway.controlUi.github.token for remote project discovery and repository previews.
        '';
      };
    };

    extraEnvironmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional systemd EnvironmentFile paths for the gateway unit.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Escape hatch merged last into the gateway config: provider catalogues, channels,
        per-agent policy. Everything provider- or tenant-specific belongs here, not in
        this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = unknownPlugins == [ ];
        message = "my.features.services.openclaw.gateway.runtimePlugins contains unknown ids: ${lib.concatStringsSep ", " unknownPlugins}";
      }
      {
        assertion = cfg.subdomain != "";
        message = "my.features.services.openclaw.gateway.subdomain must not be empty when the gateway is exposed through Caddy.";
      }
    ];

    sops.secrets = lib.genAttrs secretNames (_: { });

    sops.templates."openclaw_env" = lib.mkIf hasSecrets {
      owner = "openclaw";
      restartUnits = [ "openclaw-gateway.service" ];
      content = lib.concatLines secretEnvLines;
    };

    services.openclaw-gateway = {
      enable = true;
      port = cfg.port;
      servicePath = [
        pkgs.procps
        pkgs.git
        pkgs.gh
      ];
      environmentFiles =
        lib.optional hasSecrets config.sops.templates."openclaw_env".path ++ cfg.extraEnvironmentFiles;
      environment = {
        # Nix-managed config is read-only: refuse CLI-side plugin/config mutation.
        OPENCLAW_NIX_MODE = "1";
        OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY = "1";
      }
      // lib.optionalAttrs (cfg.gitAuthor.name != null) {
        GIT_AUTHOR_NAME = cfg.gitAuthor.name;
        GIT_COMMITTER_NAME = cfg.gitAuthor.name;
      }
      // lib.optionalAttrs (cfg.gitAuthor.email != null) {
        GIT_AUTHOR_EMAIL = cfg.gitAuthor.email;
        GIT_COMMITTER_EMAIL = cfg.gitAuthor.email;
      };
      config = lib.recursiveUpdate (
        {
          gateway = {
            port = cfg.port;
            mode = "local";
            bind = "lan";
            remote.url = remoteUrl;
            trustedProxies = [
              "127.0.0.1"
              "::1"
            ];
            auth = {
              mode = "trusted-proxy";
              identityScopes = lib.genAttrs cfg.adminUsers (_: [ "operator.admin" ]);
              trustedProxy = {
                userHeader = "x-authentik-email";
                requiredHeaders = [ "x-authentik-email" ];
                # Caddy runs on the same host, so the proxy source is loopback.
                allowLoopback = true;
                deviceAutoApprove = {
                  enabled = true;
                  scopes = [
                    "operator.read"
                    "operator.write"
                    "operator.approvals"
                    "operator.questions"
                  ];
                };
              };
            };
            controlUi = {
              enabled = true;
              allowedOrigins = [ publicUrl ] ++ cfg.controlUiExtraOrigins;
            }
            // lib.optionalAttrs (cfg.secrets.github != null) {
              github.token = "$GITHUB_TOKEN";
            };
            nodes.pairing = {
              autoApproveLocal = true;
            }
            // lib.optionalAttrs (cfg.autoApproveCidrs != [ ]) {
              autoApproveCidrs = cfg.autoApproveCidrs;
            };
          };
          models.mode = "merge";
          memory.search.provider = cfg.memorySearch;
          agents.defaults.model.primary = cfg.defaultModel;
        }
        // pluginConfig
      ) cfg.settings;
    };

    my.endpoints.openclaw = {
      host = config.networking.hostName;
      port = cfg.port;
      directAccess = {
        enable = cfg.openTailscaleFirewall;
        protocol = "tcp";
        interface = "tailscale";
      };
      proxy = {
        enable = true;
        subdomain = cfg.subdomain;
        auth = cfg.auth;
        # /j/* redeems single-use node setup codes and authenticates itself.
        # /__openclaw__/worker* is the worker handshake/bootstrap route pair.
        unauthenticatedPaths = [
          "/j/*"
          "/__openclaw__/worker*"
        ];
        # Non-browser WebSocket clients (CLI, node hosts) authenticate with bootstrap
        # or device tokens against the gateway itself.
        machineClientsBypassAuth = true;
      };
      monitoring = {
        # The Control UI answers 302 (Authentik) to unauthenticated probes.
        http.enable = false;
        tcp = {
          enable = true;
          group = "AI";
        };
      };
    };
  };
}
