{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.services.openclaw.gateway;
  stateDir = "/var/lib/openclaw";
  package = inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
  domain = config.my.contracts.provides.openclaw.publications.web.canonicalDomain;
  sandbox = config.my.contracts.provides.openclaw.publications.sandbox;
  portals = config.my.contracts.provides.openclaw.publications.portals;
  portalDomain = lib.removePrefix "*." portals.canonicalDomain;
  portalIngressPort = portals.port - 1;
  meshAddress = config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4;
  ingressAddress = config.my.topology.hosts.${config.my.topology.ingressHost}.wireguardIpv4;
  # Web search runs through the fleet's single SearXNG instance. A co-located
  # gateway uses loopback; a remote gateway uses the provider's overlay address,
  # which the machine-facing allowance already covers.
  fleetConfigs = import ../../../../lib/fleet-configs.nix { inherit lib; };
  systems = fleetConfigs.systems config;
  searxngHost = fleetConfigs.uniqueHost {
    inherit systems;
    matches = host: host.my.features.services.searxng.enable or false;
    role = "SearXNG";
  };
  searxng = systems.${searxngHost}.config.my.features.services.searxng;
  searxngAddress = config.my.topology.hosts.${searxngHost}.wireguardIpv4;
  searxngBaseUrl =
    if searxngHost == config.networking.hostName then
      "http://127.0.0.1:${toString searxng.port}"
    else
      "http://${searxngAddress}:${toString searxng.port}";
  # Home Assistant publishes the MCP server on its own contract. The gateway is
  # only a client, so the address comes from the publishing host's projection
  # rather than a second literal. The integration itself is a config entry in
  # Home Assistant; the endpoint and its options are documented there, not here.
  hassHost = fleetConfigs.uniqueHost {
    inherit systems;
    matches = host: host.my.features.services.home-assistant.enable or false;
    role = "Home Assistant";
  };
  hassMcpUrl =
    systems.${hassHost}.config.my.contracts.provides.home-assistant.publications.web.publicUrl
    + "/api/mcp";
  # Pinned runtime plugin from nix-openclaw; the load path keeps installation
  # outside the immutable config.
  searxngPlugin =
    inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}."openclaw-runtime-plugin-searxng";
  # Tokenjuice compacts noisy `exec` output after the command ran, before the
  # result reaches the session; commands and exit codes stay untouched. The
  # derivation comes from nix-openclaw's generated locks, so its version tracks
  # the gateway's: the official plugin refuses hosts below its compatibility
  # range, and the lock is generated per host release.
  tokenjuicePlugin =
    inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}."openclaw-runtime-plugin-tokenjuice";
  # Composio: ClawHub runtime plugin plus the CLI it drives. The plugin ships
  # the reviewed skill and the routing hook; the CLI performs live tool
  # discovery and execution inside the agent's exec environment.
  composioPlugin =
    pkgs.callPackage "${inputs.openclaw}/nix/lib/openclaw-runtime-plugin.nix"
      {
        openclawPackage = package;
      }
      {
        id = "composio";
        packageName = "@composio/composio";
        version = "0.1.0";
        selectedSource = "clawhub";
        sourceSpec = "clawhub:@composio/composio@0.1.0";
        nixHash = "sha256-MGeuw1lDzlG+1uqpzKfnc7ikNNfceJ0IL3BcSaBbHA0=";
        dependencyMode = "none";
        runtimeExtensions = [ "./dist/index.js" ];
        openclawCompat = ">=2026.9.1";
        peerOpenClaw = ">=2026.9.1";
      };
  subscriptions = lib.imap0 (
    index: subscription:
    subscription
    // {
      profileId = "opencode-go:${subscription.name}";
      envVar = "OPENCLAW_OPENCODE_SUBSCRIPTION_${toString index}_KEY";
    }
  ) cfg.opencodeSubscriptions;
  authPlan = pkgs.writeText "openclaw-opencode-auth-plan.json" (
    builtins.toJSON {
      version = 1;
      protocolVersion = 1;
      options = {
        scrubEnv = false;
        scrubAuthProfilesForProviderTargets = false;
      };
      targets = map (subscription: {
        type = "auth-profiles.api_key.key";
        path = "profiles.${subscription.profileId}.key";
        pathSegments = [
          "profiles"
          subscription.profileId
          "key"
        ];
        agentId = "main";
        authProfileProvider = "opencode-go";
        ref = {
          source = "env";
          provider = "default";
          id = subscription.envVar;
        };
      }) subscriptions;
    }
  );
  provisionAuth = pkgs.writeShellScript "openclaw-provision-auth" ''
    set -euo pipefail
    # The upstream secrets CLI always invokes its config writer, even for
    # auth-store-only plans. Keep that write away from the immutable Nix config.
    temporary=$(mktemp -d)
    trap 'rm -rf "$temporary"' EXIT
    cp /etc/openclaw/openclaw.json "$temporary/openclaw.json"
    OPENCLAW_CONFIG_PATH="$temporary/openclaw.json" \
      CLAWDBOT_CONFIG_PATH="$temporary/openclaw.json" \
      OPENCLAW_NIX_MODE=0 \
      ${package}/bin/openclaw secrets apply --from ${authPlan} --json
  '';
  operator = pkgs.writeShellScriptBin "openclaw-gateway-admin" ''
    set -euo pipefail
    if [ "$EUID" -ne 0 ]; then
      echo "Run with sudo: openclaw-gateway-admin <command>" >&2
      exit 1
    fi
    export HOME=${stateDir}
    export OPENCLAW_STATE_DIR=${stateDir}
    export OPENCLAW_CONFIG_PATH=/etc/openclaw/openclaw.json
    unset OPENCLAW_GATEWAY_TOKEN
    export OPENCLAW_GATEWAY_PASSWORD="$(< ${config.sops.secrets."openclaw/gateway_password".path})"
    ${lib.concatMapStringsSep "\n" (subscription: ''
      export ${subscription.envVar}="$(< ${config.sops.secrets.${subscription.apiKeySecret}.path})"
    '') subscriptions}
    export OPENCODE_API_KEY="$${(builtins.head subscriptions).envVar}"
    export OPENROUTER_API_KEY="$(< ${config.sops.secrets."ai/openrouter_api_key".path})"
    export OPENAI_API_KEY="$(< ${config.sops.secrets."ai/openai_api_key".path})"
    exec ${pkgs.util-linux}/bin/runuser -u openclaw -- ${package}/bin/openclaw "$@"
  '';
in
{
  imports = [ inputs.openclaw.nixosModules.openclaw-gateway ];

  options.my.features.services.openclaw.gateway = {
    enable = lib.mkEnableOption "the central native OpenClaw gateway";
    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Gateway HTTP and WebSocket port on the mesh interface.";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
      description = "Public gateway subdomain under the site's service domain.";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "opencode-go/deepseek-v4.1-flash";
      description = "Default provider/model reference for the native OpenClaw runtime.";
    };
    opencodeSubscriptions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.strMatching "[a-zA-Z0-9-]+";
              description = "Stable subscription name used for the OpenClaw auth profile.";
            };
            apiKeySecret = lib.mkOption {
              type = lib.types.str;
              description = "SOPS secret containing this subscription's API key.";
            };
          };
        }
      );
      default = [
        {
          name = "subscription-1";
          apiKeySecret = "ai/opencode_api_key";
        }
      ];
      description = "OpenCode Go subscriptions in preferred auth failover order.";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional OpenClaw settings; credentials belong in runtime secret files.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = meshAddress != null && ingressAddress != null;
        message = "OpenClaw gateway and ingress require inventory mesh addresses.";
      }
      {
        assertion =
          subscriptions != [ ]
          &&
            lib.length (lib.unique (map (subscription: subscription.name) subscriptions))
            == lib.length subscriptions;
        message = "OpenClaw requires at least one OpenCode subscription with unique names.";
      }
      {
        assertion = searxngHost == config.networking.hostName || searxngAddress != null;
        message = "OpenClaw web search requires the SearXNG host's overlay address.";
      }
    ];

    sops.secrets = lib.genAttrs (
      [
        "openclaw/gateway_password"
        "ai/openrouter_api_key"
        "ai/openai_api_key"
        "services/home/hass_mcp_token"
      ]
      ++ map (subscription: subscription.apiKeySecret) subscriptions
    ) (_: { });
    sops.templates.openclaw-gateway-env.content = ''
      OPENCLAW_GATEWAY_PASSWORD=${config.sops.placeholder."openclaw/gateway_password"}
      HASS_MCP_TOKEN=${config.sops.placeholder."services/home/hass_mcp_token"}
      ${lib.concatMapStringsSep "\n" (
        subscription: "${subscription.envVar}=${config.sops.placeholder.${subscription.apiKeySecret}}"
      ) subscriptions}
      OPENCODE_API_KEY=${config.sops.placeholder.${(builtins.head subscriptions).apiKeySecret}}
      OPENROUTER_API_KEY=${config.sops.placeholder."ai/openrouter_api_key"}
      OPENAI_API_KEY=${config.sops.placeholder."ai/openai_api_key"}
    '';
    sops.templates.openclaw-gateway-env.restartUnits = [ "openclaw-gateway.service" ];

    services.openclaw-gateway = {
      enable = true;
      inherit package stateDir;
      inherit (cfg) port;
      environmentFiles = [ config.sops.templates.openclaw-gateway-env.path ];
      environment.HOME = stateDir;
      servicePath = [
        pkgs.gh
        pkgs.git
        pkgs.ripgrep
        pkgs.nix
      ];
      config = lib.recursiveUpdate {
        auth = {
          profiles = lib.listToAttrs (
            map (
              subscription:
              lib.nameValuePair subscription.profileId {
                provider = "opencode-go";
                mode = "api_key";
              }
            ) subscriptions
          );
          order.opencode-go = map (subscription: subscription.profileId) subscriptions;
        };
        gateway = {
          mode = "local";
          port = cfg.port;
          # Native CLI administration requires a real loopback connection.
          # The firewall admits remote traffic only from the ingress over WG.
          bind = "lan";
          publicOrigin = "https://${domain}";
          trustedProxies = [ ingressAddress ];
          auth = {
            mode = "trusted-proxy";
            password = "\${OPENCLAW_GATEWAY_PASSWORD}";
            allowTailscale = false;
            identityScopes.${config.my.user.primary} = [ "operator.admin" ];
            trustedProxy = {
              userHeader = "X-Authentik-Username";
              requiredHeaders = [ "X-Authentik-Uid" ];
              allowUsers = [ config.my.user.primary ];
              allowLoopback = false;
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
          controlUi.allowedOrigins = [ "https://${domain}" ];
          controlUi.experimental.customPlugins = true;
          portals.ingress = {
            domain = portalDomain;
            port = portalIngressPort;
          };
          # Authored explicitly: the runtime default is enabled, but an unset
          # value reads as "not configured" in configuration surfaces.
          uploads.enabled = true;
          nodes = {
            browser.mode = "auto";
            # Every File Transfer command is classified dangerous, so no platform default
            # ever carries one and this list is the only way in. camera.list is a Linux
            # plugin default; the two capture commands are the same opt-in shape as the
            # file commands. The file-transfer workspace commands stay out on purpose:
            # they relocate an agent's workspace onto a node rather than grant file access.
            commands.allow = [
              "dir.list"
              "dir.fetch"
              "file.stat"
              "file.fetch"
              "file.write"
              "file.create"
              "camera.snap"
              "camera.clip"
            ];
          };
        };
        browser = {
          enabled = true;
          executablePath = lib.getExe pkgs.chromium;
          headless = true;
          defaultProfile = "openclaw";
          profiles.openclaw.cdpPort = 18800;
        };
        agents.defaults = {
          model.primary = cfg.model;
          # An explicit empty policy disables legacy restrictions inferred from
          # model settings and keeps the provider's discovered catalog selectable.
          modelPolicy = { };
          heartbeat = {
            every = "1h";
            lightContext = true;
            isolatedSession = true;
            # Browser/app users have no external channel delivery route.
            target = "none";
          };
        };
        cron.enabled = true;
        # Widgets and MCP Apps share a public shell on a separate origin.
        # Documents themselves arrive over the authenticated gateway connection.
        mcp.apps = {
          sandboxOrigin = sandbox.publicUrl;
          sandboxPort = sandbox.port;
        };
        memory.search = {
          enabled = true;
          rememberAcrossConversations = true;
          sources = [
            "memory"
            "sessions"
          ];
          provider = "openai-compatible";
          model = "openai/text-embedding-3-small";
          remote = {
            baseUrl = "https://openrouter.ai/api/v1";
            apiKey = "\${OPENROUTER_API_KEY}";
          };
        };
        talk = {
          provider = "openrouter";
          providers.openrouter = {
            modelId = "google/gemini-3.1-flash-tts-preview";
            speakerVoice = "Kore";
            responseFormat = "mp3";
            apiKey = "\${OPENROUTER_API_KEY}";
          };
          speechLocale = "de-DE";
          interruptOnSpeech = true;
          realtime = {
            provider = "openai";
            providers.openai = {
              model = "gpt-live-1";
              speakerVoice = "marin";
              apiKey = "\${OPENAI_API_KEY}";
            };
            mode = "realtime";
            # Android requires the relay; the browser supports it as well.
            transport = "gateway-relay";
            brain = "agent-consult";
          };
        };
        discovery.mdns.mode = "off";
        # Home Assistant's MCP server authenticates with a long-lived access
        # token from an admin account, so the header carries the sops value and
        # no OAuth flow is involved. Every tool the server offers stays
        # available: the actuators are the point of the integration, and a
        # client-side allowlist would hide them behind a second list that does
        # not track upstream tool names.
        mcp.servers.hass = {
          url = hassMcpUrl;
          transport = "streamable-http";
          enabled = true;
          headers.Authorization = "Bearer \${HASS_MCP_TOKEN}";
        };
        plugins.entries.acpx.enabled = false;
        plugins.entries.openrouter.enabled = true;
        plugins.entries.openai.enabled = true;
        plugins.entries.workboard.enabled = true;
        # The plugin denies every call until a node entry exists, even when the node
        # command itself is allowed. `*` is the fleet-wide key that node-policy resolution
        # falls back to, and `/**` admits every path on every node for reads and writes
        # alike; the gateway host runs no node service, so its own state stays out of
        # reach. Standing approvals cannot be recorded here anyway: the config file is
        # Nix-owned and immutable, so the policy is authored rather than approved per call.
        plugins.entries.file-transfer.config = {
          policyVersion = 2;
          nodes."*" = {
            ask = "off";
            followSymlinks = true;
            allowReadPaths = [ "/**" ];
            allowWritePaths = [ "/**" ];
          };
        };
        plugins.load.paths = [
          "${searxngPlugin}"
          "${composioPlugin}"
          "${tokenjuicePlugin}"
        ];
        plugins.entries.searxng = {
          enabled = true;
          config.webSearch.baseUrl = searxngBaseUrl;
        };
        plugins.entries.composio = {
          enabled = true;
          hooks.allowConversationAccess = true;
        };
        plugins.entries.tokenjuice.enabled = true;
        tools.exec.pathPrepend = [
          "${pkgs.gh}/bin"
          "${pkgs.custom.composio}/bin"
        ];
        tools.web.search = {
          enabled = true;
          provider = "searxng";
        };
        plugins.entries.active-memory = {
          enabled = true;
          config = {
            enabled = true;
            mode = "escalate";
            allowedChatTypes = [
              "direct"
              "explicit"
            ];
          };
        };
        plugins.entries.memory-core = {
          enabled = true;
          config.dreaming.enabled = true;
        };
        plugins.entries.device-pair.config.publicUrl = "https://${domain}";
        logging.file = "${stateDir}/logs/openclaw.log";
      } cfg.settings;
    };

    systemd.services.openclaw-gateway = {
      after = [ "wireguard-wg0.service" ];
      restartTriggers = [
        config.environment.etc."openclaw/openclaw.json".source
        authPlan
      ];
      serviceConfig = {
        UMask = "0077";
        StandardOutput = lib.mkForce "journal";
        StandardError = lib.mkForce "journal";
        ExecStartPre = [ provisionAuth ];
      };
    };
    environment.systemPackages = [ operator ];

    # OpenClaw keeps portal ingress on loopback. Expose only a mesh socket to
    # the contract-admitted ingress, preserving the original HTTP Host header.
    systemd.sockets.openclaw-portals = {
      wantedBy = [ "sockets.target" ];
      after = [ "wireguard-wg0.service" ];
      requires = [ "wireguard-wg0.service" ];
      listenStreams = [ "${meshAddress}:${toString portals.port}" ];
      socketConfig.NoDelay = true;
    };
    systemd.services.openclaw-portals = {
      requires = [ "openclaw-gateway.service" ];
      after = [ "openclaw-gateway.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString portalIngressPort}";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    my.contracts.provides.openclaw = {
      endpoints.portals = {
        port = cfg.port + 102;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          fromHosts = [ config.my.topology.ingressHost ];
        };
      };
      publications.portals = {
        scope = "public";
        endpoint = "portals";
        subdomain = "*.preview.${cfg.subdomain}";
        extraDomains = [ portalDomain ];
        ingressOnly = true;
        auth = "authentik";
        accessUsers = [ config.my.user.primary ];
        proxyOptions = ''
          header_up -X-Authentik-*
          flush_interval -1
          transport http {
            read_timeout 3600s
            write_timeout 3600s
          }
        '';
      };
      endpoints.sandbox = {
        port = cfg.port + 1;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
          fromHosts = [ config.my.topology.ingressHost ];
        };
      };
      publications.sandbox = {
        scope = "public";
        endpoint = "sandbox";
        subdomain = "sandbox.${cfg.subdomain}";
        ingressOnly = true;
        auth = "none";
        publicExempt = "Isolated widget shell and public renderer assets only; private documents use the authenticated gateway connection.";
      };
      endpoints.http = {
        port = cfg.port;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
          fromHosts = [ config.my.topology.ingressHost ];
        };
      };
      publications.web = {
        scope = "public";
        endpoint = "http";
        subdomain = cfg.subdomain;
        auth = "authentik";
        accessUsers = [ config.my.user.primary ];
        ingressOnly = true;
        # These transports carry OpenClaw bootstrap, worker or paired-device
        # credentials. Browser traffic still passes through the identity gate.
        unauthenticatedPaths = [
          "/j/*"
          "/__openclaw__/worker"
        ];
        machineClientsBypassAuth = true;
        stripRequestHeaders = [
          "Forwarded"
          "X-Real-IP"
          "X-Forwarded-User"
        ];
        proxyOptions = ''
          flush_interval -1
          transport http {
            read_timeout 3600s
            write_timeout 3600s
          }
        '';
      };
      storage.dataDirs = [ stateDir ];
      backup.exclude = [ "${stateDir}/logs" ];
    };
  };
}
