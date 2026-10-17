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
    export OPENCODE_API_KEY="$(< ${config.sops.secrets."ai/opencode_api_key".path})"
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
    ];

    sops.secrets."openclaw/gateway_password" = { };
    sops.secrets."ai/opencode_api_key" = { };
    sops.templates.openclaw-gateway-env.content = ''
      OPENCLAW_GATEWAY_PASSWORD=${config.sops.placeholder."openclaw/gateway_password"}
      OPENCODE_API_KEY=${config.sops.placeholder."ai/opencode_api_key"}
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
          models.${cfg.model}.agentRuntime.id = "openclaw";
          heartbeat.every = "0m";
        };
        cron.enabled = false;
        discovery.mdns.mode = "off";
        plugins.entries.acpx.enabled = false;
        plugins.entries.device-pair.config.publicUrl = "https://${domain}";
        logging.file = "${stateDir}/logs/openclaw.log";
      } cfg.settings;
    };

    systemd.services.openclaw-gateway = {
      after = [ "wireguard-wg0.service" ];
      restartTriggers = [ config.environment.etc."openclaw/openclaw.json".source ];
      serviceConfig = {
        UMask = "0077";
        StandardOutput = lib.mkForce "journal";
        StandardError = lib.mkForce "journal";
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
