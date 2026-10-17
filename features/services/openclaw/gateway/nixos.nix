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
  # Pinned runtime plugin from nix-openclaw; the load path keeps installation
  # outside the immutable config.
  searxngPlugin =
    inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}."openclaw-runtime-plugin-searxng";
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
      ]
      ++ map (subscription: subscription.apiKeySecret) subscriptions
    ) (_: { });
    sops.templates.openclaw-gateway-env.content = ''
      OPENCLAW_GATEWAY_PASSWORD=${config.sops.placeholder."openclaw/gateway_password"}
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
        plugins.entries.acpx.enabled = false;
        plugins.entries.openrouter.enabled = true;
        plugins.entries.openai.enabled = true;
        plugins.load.paths = [ "${searxngPlugin}" ];
        plugins.entries.searxng = {
          enabled = true;
          config.webSearch.baseUrl = searxngBaseUrl;
        };
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

    my.contracts.provides.openclaw = {
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
