# features/services/openclaw/default.nix — OpenClaw Agent Gateway and Node feature module
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.openclaw;
  rollinsTailscaleIp =
    config.my.features.system.networking.topology.hosts.rollins.tailscaleIp or "127.0.0.1";
in
{
  options.my.features.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI service";

    role = lib.mkOption {
      type = lib.types.enum [
        "gateway"
        "node"
      ];
      default = "node";
      description = "Whether to run OpenClaw as central Gateway (server) or companion Node (client).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Internal port the OpenClaw gateway listens on.";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ai";
      description = "Subdomain for OpenClaw web UI / gateway under caddy.baseDomain (e.g. ai.rls.ancoris.ovh).";
    };

    auth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to protect the web UI via Authentik forward-auth in Caddy.";
    };

    adminUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of user emails from Authentik that are granted full operator.admin scopes.";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "ws://${rollinsTailscaleIp}:${toString cfg.port}";
      description = "Gateway WebSocket URL that the node connects to.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Declarative OpenClaw configuration merged into openclaw.json.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of environment files passed to the OpenClaw systemd service.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # --- GATEWAY MODE ---
      (lib.mkIf (cfg.role == "gateway") {
        sops.templates."openclaw_env" = {
          owner = "openclaw";
          restartUnits = [ "openclaw-gateway.service" ];
          content = ''
            ${lib.optionalString (config.sops.secrets ? "pi/deepseek")
              "DEEPSEEK_API_KEY=${config.sops.placeholder."pi/deepseek"}"
            }
          '';
        };

        services.openclaw-gateway = {
          enable = true;
          port = cfg.port;
          environmentFiles = [ config.sops.templates."openclaw_env".path ] ++ cfg.environmentFiles;
          config = lib.recursiveUpdate {
            gateway = {
              port = cfg.port;
              mode = "local";
              trustedProxies = [
                "127.0.0.1"
                "::1"
              ];
              auth = {
                mode = "trusted-proxy";
                identityScopes = lib.genAttrs cfg.adminUsers (_: [ "operator.admin" ]);
                trustedProxy = {
                  userHeader = "x-authentik-email";
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
                dangerouslyAllowHostHeaderOriginFallback = true;
                allowedOrigins = [
                  "https://${cfg.subdomain}.${config.my.features.services.caddy.baseDomain}"
                ];
              };
            };
            models = {
              mode = "merge";
              providers = {
                deepseek = {
                  baseUrl = "https://api.deepseek.com";
                  api = "openai-completions";
                  models = [
                    {
                      id = "deepseek-flash";
                      name = "DeepSeek Flash";
                      reasoning = false;
                      input = [ "text" ];
                      contextWindow = 64000;
                      maxTokens = 8192;
                    }
                    {
                      id = "deepseek-chat";
                      name = "DeepSeek Chat";
                      reasoning = false;
                      input = [ "text" ];
                      contextWindow = 64000;
                      maxTokens = 8192;
                    }
                  ];
                };
              };
            };
            agents = {
              defaults = {
                model = {
                  primary = "deepseek/deepseek-flash";
                };
              };
            };
          } cfg.settings;
        };

        # Register endpoint for Caddy reverse proxy and firewall
        my.endpoints.openclaw = {
          host = config.networking.hostName;
          port = cfg.port;
          proxy = {
            enable = true;
            subdomain = cfg.subdomain;
            auth = cfg.auth;
            websocket = true;
          };
          monitoring = {
            http = {
              enable = true;
              group = "AI";
              path = "/";
            };
          };
        };
      })

      # --- NODE MODE ---
      (lib.mkIf (cfg.role == "node") {
        systemd.services.openclaw-node = {
          description = "OpenClaw Companion Node";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "tailscaled.service"
          ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "simple";
            DynamicUser = true;
            StateDirectory = "openclaw-node";
            WorkingDirectory = "/var/lib/openclaw-node";
            ExecStart = "${pkgs.openclaw}/bin/openclaw node run --gateway ${cfg.gatewayUrl}";
            Restart = "always";
            RestartSec = 5;
          };

          path = [
            pkgs.bash
            pkgs.coreutils
            pkgs.nix
          ];
        };
      })
    ]
  );
}
