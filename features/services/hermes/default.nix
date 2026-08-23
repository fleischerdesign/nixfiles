# features/services/hermes/default.nix — Hermes Agent feature module
#
# Self-contained NixOS module for the Hermes AI agent. No upstream flake
# dependency — the agent is built from source via buildPythonPackage
# (package.nix) with npm-based web assets for the gateway UI.
#
# Architecture:
#   Core (this file)        Options, systemd service, config generation,
#                           subdomain delegation, secrets, users.
#   package.nix             Two-phase derivation: buildPythonPackage for
#                           the Python application, stdenv.mkDerivation
#                           for asset symlinks and binary wrappers.
#   mcp.nix                 Typed MCP server options bridged into the
#                           free-form settings attrset.
#   extensions/<name>/      Each extension provides its own nixos.nix
#                           (options + config) and optionally package.nix.
#                           Extensions are gated by explicit enable flags.
#
# Design decisions:
#   - buildPythonPackage with empty propagatedBuildInputs → dependencies
#     are provided by pythonEnv (withPackages). This separates the
#     application build from its runtime environment, allowing
#     extension packages to be injected without rebuilding the core.
#   - Config is serialized as JSON (YAML superset) and written once
#     on first boot. The agent's runtime settings are fully declarative
#     via services.hermes-agent.settings.
#   - Subdomain delegation uses a host-level Caddy wildcard TLS
#     (Cloudflare DNS challenge) that reverse-proxies to an internal
#     Caddy instance running as the hermes user.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.hermes;

  corePackage = pkgs.callPackage ./package.nix {
    extraPythonPackages =
      (lib.optionals cfg.extensions.mnemosyne.enable [
        (pkgs.callPackage ./extensions/mnemosyne/package.nix { }).memory
        (pkgs.callPackage ./extensions/mnemosyne/package.nix { }).hermes
      ])
      ++ (lib.optionals cfg.extensions.ddgs.enable [
        (pkgs.callPackage ./extensions/ddgs/package.nix { })
      ])
      ++ (lib.optionals cfg.integrations.telegram.enable [
        pkgs.python3Packages.python-telegram-bot
      ]);

    inherit (pkgs) nodejs_22;
  };

  configJson = builtins.toJSON (
    lib.recursiveUpdate { terminal.cwd = cfg.workingDirectory; } config.services.hermes-agent.settings
  );

  generatedConfigFile = pkgs.writeText "hermes-config.yaml" configJson;

  hermesHome = cfg.stateDir + "/.hermes";

  sub = cfg.subdomainDelegation;
  inherit (sub) baseDomain;

  mkNullableEnv = lib.filterAttrs (_: v: v != null);

  agentEnv = mkNullableEnv (
    {
      MNEMOSYNE_EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2";
      HASS_URL = cfg.integrations.hass.url;
      PAPERLESS_URL = cfg.integrations.paperless.url;
      CAMOFOX_URL = cfg.integrations.camofox.url;
    }
    // lib.optionalAttrs cfg.integrations.vikunja.enable {
      VIKUNJA_URL = cfg.integrations.vikunja.url;
    }
  );

  agentSettings =
    lib.recursiveUpdate
      {
        approvals.mode = "smart";
        model = {
          default = cfg.model;
          provider = cfg.provider;
        };
        memory = {
          provider = "mnemosyne";
          memory_enabled = true;
        };
        inherit (cfg) auxiliary;
        terminal.backend = "local";
      }
      (
        if cfg.integrations.telegram.enable && cfg.integrations.telegram.chatId != null then
          {
            platforms.telegram.home_channel = {
              platform = "telegram";
              chat_id = cfg.integrations.telegram.chatId;
            };
          }
        else
          { }
          // (
            if cfg.integrations.camofox.enable then
              {
                browser.camofox.managed_persistence = true;
              }
            else
              { }
          )
          // (
            if sub.enable then
              {
                platforms.webhook = {
                  enabled = true;
                  extra = {
                    port = 8644;
                    host = "127.0.0.1";
                  };
                };
              }
            else
              { }
          )
      );

  modelOption = lib.types.submodule {
    options = {
      model = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Model name.";
      };
      provider = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Model provider.";
      };
    };
  };
in
{
  imports = [
    ./mcp.nix
    ./extensions/webui/nixos.nix
    ./extensions/mnemosyne/nixos.nix
    ./extensions/ddgs/nixos.nix
    ./extensions/obsidian/nixos.nix
  ];

  options = {
    services.hermes-agent = {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Hermes agent config merged into config.yaml.";
      };
      environmentFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Environment files loaded by the hermes-agent service.";
      };
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment variables for the hermes-agent service.";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra CLI arguments passed to hermes gateway.";
      };
      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Packages added to the service PATH.";
      };
    };

    my.features.services.hermes = {
      enable = lib.mkEnableOption "Hermes Agent";
      provider = lib.mkOption {
        type = lib.types.str;
        default = "openrouter";
        description = "Default model provider for Hermes Agent.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "deepseek/deepseek-chat";
        description = "Default model for Hermes Agent.";
      };

      auxiliary = lib.mkOption {
        type = lib.types.submodule {
          options = {
            vision = lib.mkOption {
              type = modelOption;
              default = { };
              description = "Vision/image model configuration.";
            };
            title_generation = lib.mkOption {
              type = modelOption;
              default = { };
              description = "Title generation model configuration.";
            };
            compression = lib.mkOption {
              type = modelOption;
              default = { };
              description = "Compression model configuration.";
            };
            approval = lib.mkOption {
              type = modelOption;
              default = { };
              description = "Approval model configuration.";
            };
            web_extract = lib.mkOption {
              type = modelOption;
              default = { };
              description = "Web extraction model configuration.";
            };
          };
        };
        default = { };
        description = "Auxiliary model configurations.";
      };

      hostUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.optionals (config ? my && config.my ? user && config.my.user ? primary) [
          config.my.user.primary
        ];
        description = "Interactive host users in the hermes group.";
      };
      workingDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/hermes/workspace";
        description = "Working directory for the agent service.";
      };
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/hermes";
        description = "State directory for hermes-agent. HERMES_HOME is set to stateDir/.hermes.";
      };

      soulContent = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SOUL.md identity content. Written once to HERMES_HOME via tmpfiles C-type. Null by default — set per host. To update after initial deploy, delete the target file and redeploy.";
      };

      subdomainDelegation = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "wildcard subdomain delegation via Caddy";
            baseDomain = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = config.my.features.services.caddy.baseDomain or null;
              description = "Base domain for wildcard routing.";
            };
            prefix = lib.mkOption {
              type = lib.types.str;
              default = "hermes";
              description = "Subdomain prefix for routing (e.g. webhook.{prefix}.{baseDomain}).";
            };
          };
        };
        default = { };
      };

      integrations = lib.mkOption {
        type = lib.types.submodule {
          options = {
            hass = {
              enable = lib.mkEnableOption "Home Assistant integration";
              url = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Home Assistant URL.";
              };
            };
            paperless = {
              enable = lib.mkEnableOption "Paperless integration";
              url = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Paperless URL.";
              };
            };
            camofox = {
              enable = lib.mkEnableOption "Camofox browser integration";
              url = lib.mkOption {
                type = lib.types.str;
                default = "http://127.0.0.1:9377";
                description = "Camofox browser URL.";
              };
            };
            telegram = {
              enable = lib.mkEnableOption "Telegram integration";
              chatId = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Telegram Chat ID for home_channel.";
              };
            };
            vikunja = {
              enable = lib.mkEnableOption "Vikunja task management integration";
              url = lib.mkOption {
                type = lib.types.str;
                default = "https://vikunja.mky.ancoris.ovh";
                description = "Vikunja URL.";
              };
            };
          };
        };
        default = { };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      hermes_agent_env = {
        owner = "hermes";
        restartUnits = [ "hermes-agent.service" ];
      };
    }
    // lib.optionalAttrs cfg.integrations.camofox.enable {
      camofox_api_key.restartUnits = lib.mkDefault [ "hermes-agent.service" ];
    }
    // lib.optionalAttrs cfg.integrations.vikunja.enable {
      vikunja_api_token.restartUnits = lib.mkDefault [ "hermes-agent.service" ];
    }
    // lib.optionalAttrs sub.enable {
      cloudflare_api_token = { };
    };

    sops.templates."hermes_env" = {
      owner = "hermes";
      restartUnits = [
        "hermes-agent.service"
        "hermes-webui.service"
      ];
      content = ''
        ${lib.optionalString (config.sops.secrets ? "pi/openrouter")
          "OPENROUTER_API_KEY=${config.sops.placeholder."pi/openrouter"}"
        }
        ${lib.optionalString cfg.integrations.camofox.enable "CAMOFOX_API_KEY=${config.sops.placeholder.camofox_api_key}"}
        ${lib.optionalString cfg.integrations.vikunja.enable "VIKUNJA_API_TOKEN=${config.sops.placeholder.vikunja_api_token}"}
      '';
    };

    services.hermes-agent = {
      settings = agentSettings;
      environmentFiles = [
        config.sops.secrets.hermes_agent_env.path
        config.sops.templates."hermes_env".path
      ];
      environment = agentEnv;
      extraPackages = with pkgs; [
        nix
        gh
        antigravity-cli
      ];
    };

    systemd.services.hermes-agent = {
      description = "Hermes Agent Gateway";
      restartTriggers = [ generatedConfigFile ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        Group = "hermes";
        ExecStart = "${corePackage}/bin/hermes gateway ${lib.escapeShellArgs config.services.hermes-agent.extraArgs}";
        Restart = "always";
        RestartSec = 5;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") config.services.hermes-agent.environment;
        EnvironmentFile = map builtins.toString config.services.hermes-agent.environmentFiles;
        WorkingDirectory = cfg.workingDirectory;
      };

      path = config.services.hermes-agent.extraPackages;
    };

    environment.systemPackages = [ corePackage ];
    environment.variables.HERMES_HOME = hermesHome;

    systemd.services.hermes-webui.restartTriggers = [ generatedConfigFile ];

    system.activationScripts."hermes-agent-config" = lib.stringAfter [ "users" ] ''
      mkdir -p ${hermesHome}
      chown hermes:hermes ${hermesHome}

      ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 << 'PYEOF'
      import yaml, json, sys

      nix_path = "${generatedConfigFile}"
      config_path = "${hermesHome}/config.yaml"
      dry_run = False

      try:
          with open(nix_path) as f:
              nix_cfg = yaml.safe_load(f)
      except Exception as e:
          print(f"[hermes-config] failed to read nix config: {e}", file=sys.stderr)
          sys.exit(1)

      existing = {}
      try:
          with open(config_path) as f:
              existing = yaml.safe_load(f) or {}
      except FileNotFoundError:
          pass

      def deep_merge(base, override):
          for k, v in override.items():
              if isinstance(v, dict) and isinstance(base.get(k), dict):
                  base[k] = deep_merge(dict(base[k]), v)
              else:
                  base[k] = v
          return base

      merged = deep_merge(existing, nix_cfg)

      with open(config_path, "w") as f:
          yaml.safe_dump(merged, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

      print("[hermes-config] wrote merged config.yaml")
      PYEOF

      chown hermes:hermes ${hermesHome}/config.yaml
      chmod 0640 ${hermesHome}/config.yaml
    '';

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir}            2770 hermes hermes - -"
      "d ${hermesHome}              2770 hermes hermes - -"
      "d ${cfg.workingDirectory}    2770 hermes hermes - -"
      "d ${cfg.stateDir}/.gemini    0770 hermes hermes -"
      "d ${cfg.stateDir}/.config    0770 hermes hermes -"
      "d ${cfg.stateDir}/.config/gh 0770 hermes hermes -"
      "f /var/lib/systemd/linger/hermes 0644 root root - -"
    ]
    ++ lib.optionals (cfg.soulContent != null) [
      "C ${hermesHome}/SOUL.md 0640 hermes hermes - ${pkgs.writeText "hermes-soul.md" cfg.soulContent}"
    ];

    users.users =
      (lib.genAttrs cfg.hostUsers (_: {
        extraGroups = [ "hermes" ];
      }))
      // {
        hermes = {
          home = lib.mkForce cfg.stateDir;
          homeMode = lib.mkDefault "2750";
        };
      };

    users.groups.hermes = { };

    services.caddy.package = lib.mkIf sub.enable (
      pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-7GoH8YLCoPmPExQxoga2FHB58zQDoZVf1BBwkVi0SsQ=";
      }
    );

    sops.templates.caddy_env.content = lib.mkIf sub.enable ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare_api_token}
    '';

    services.caddy.environmentFile = lib.mkIf sub.enable config.sops.templates.caddy_env.path;

    services.caddy.virtualHosts."*.${sub.prefix}.${baseDomain}" = lib.mkIf sub.enable {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        @${sub.prefix} host *.${sub.prefix}.${baseDomain}
        handle @${sub.prefix} {
          reverse_proxy 127.0.0.1:4480
        }
      '';
    };

    systemd.services.hermes-agent-caddy = lib.mkIf sub.enable {
      description = "Caddy for Hermes Agent Subdomain Delegation";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.caddy}/bin/caddy run --config ${hermesHome}/caddy/Caddyfile --adapter caddyfile";
        ExecReload = "${pkgs.caddy}/bin/caddy reload --config ${hermesHome}/caddy/Caddyfile --address localhost:2020";
        User = "hermes";
        Group = "hermes";
        Restart = "always";
        WorkingDirectory = cfg.stateDir;
      };
    };

    systemd.services.hermes-agent-moebius-bootstrap = lib.mkIf sub.enable {
      description = "Bootstrap Caddy for Hermes subdomain routing";
      wantedBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent-caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        User = "hermes";
        Group = "hermes";
      };
      script = ''
        mkdir -p ${hermesHome}/caddy/routes

        cat > ${hermesHome}/caddy/Caddyfile << 'CADDYEOF'
        {
          admin localhost:2020
          auto_https off
        }

        :4480 {
          import ${hermesHome}/caddy/routes/*
        }
        CADDYEOF

        cat > ${hermesHome}/caddy/routes/webhook << ROUTEEOF
        @webhook host webhook.${sub.prefix}.${baseDomain}
        handle @webhook {
          rewrite * /webhooks{path}
          reverse_proxy 127.0.0.1:8644 {
            transport http
          }
        }
        ROUTEEOF

        cat > ${hermesHome}/caddy/routes/health << ROUTEEOF
        @health host health.${sub.prefix}.${baseDomain}
        handle @health {
          reverse_proxy 127.0.0.1:8090 {
            transport http
          }
        }
        ROUTEEOF

        systemctl reload hermes-agent-caddy.service 2>/dev/null || true
      '';
    };
  };
}
