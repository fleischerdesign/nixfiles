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
{ config, lib, pkgs, ... }:
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
      ]);

    inherit (pkgs) nodejs_22;
  };

  configJson = builtins.toJSON (
    lib.recursiveUpdate { terminal.cwd = cfg.workingDirectory; } config.services.hermes-agent.settings
  );

  generatedConfigFile = pkgs.writeText "hermes-config.yaml" configJson;

  hermesHome = cfg.stateDir + "/.hermes";

  baseDomain = config.my.features.services.caddy.baseDomain;
  sub = cfg.subdomainDelegation;

  mkNullableEnv = lib.filterAttrs (_: v: v != null);

  agentEnv = mkNullableEnv ({
    MNEMOSYNE_EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2";
    HASS_URL = cfg.integrations.hass.url;
    PAPERLESS_URL = cfg.integrations.paperless.url;
    CAMOFOX_URL = cfg.integrations.camofox.url;
  } // lib.optionalAttrs (cfg.integrations.camofox.url != null) {
    CAMOFOX_API_KEY = config.sops.placeholder.camofox_api_key;
  });

  agentSettings = lib.recursiveUpdate {
    approvals.mode = "smart";
    model = {
      default = cfg.model;
      provider = "deepseek";
    };
    memory = {
      provider = "mnemosyne";
      memory_enabled = false;
      user_profile_enabled = false;
    };
    auxiliary = {
      vision = {
        provider = "openrouter";
        model = "google/gemini-3.5-flash";
      };
      title_generation = {
        provider = "deepseek";
        model = "deepseek-v4-flash";
      };
      compression = {
        provider = "deepseek";
        model = "deepseek-v4-flash";
      };
      approval = {
        provider = "deepseek";
        model = "deepseek-v4-flash";
      };
      web_extract = {
        provider = "deepseek";
        model = "deepseek-v4-flash";
      };
    };
    terminal.backend = "local";
  } (
    if cfg.integrations.telegram.chatId != null then {
      platforms.telegram.home_channel = {
        platform = "telegram";
        chat_id = cfg.integrations.telegram.chatId;
      };
    } else { }
    // (
      if cfg.integrations.camofox.url != null then {
        browser.camofox.managed_persistence = true;
      } else { }
    )
    // (
      if sub.enable then {
        platforms.webhook = {
          enabled = true;
          extra = {
            port = 8644;
            host = "127.0.0.1";
          };
        };
      } else { }
    )
  );
in
{
  imports = [
    ./mcp.nix
    ./extensions/webui/nixos.nix
    ./extensions/mnemosyne/nixos.nix
    ./extensions/ddgs/nixos.nix
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
      model = lib.mkOption {
        type = lib.types.str;
        default = "deepseek-v4-flash";
        description = "Default model for Hermes Agent.";
      };
      hostUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ config.my.user.name ];
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

      subdomainDelegation = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "wildcard subdomain delegation via Caddy";
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
            hass.url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Home Assistant URL. When null, no HASS_URL env var is set.";
            };
            paperless.url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Paperless URL. When null, no PAPERLESS_URL env var is set.";
            };
            camofox.url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Camofox browser URL. When null, camofox API key and env vars are absent.";
            };
            telegram.chatId = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Telegram Chat ID for home_channel. When null, telegram config is absent.";
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
    } // lib.optionalAttrs (cfg.integrations.camofox.url != null) {
      camofox_api_key.restartUnits = lib.mkDefault [ "hermes-agent.service" ];
    } // lib.optionalAttrs (sub.enable) {
      cloudflare_api_token = { };
    };

    services.hermes-agent = {
      settings = agentSettings;
      environmentFiles = [ config.sops.secrets.hermes_agent_env.path ];
      environment = agentEnv;
      extraPackages = with pkgs; [
        nix
        gh
        antigravity-cli
      ];
    };

    systemd.services.hermes-agent = {
      description = "Hermes Agent Gateway";
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

    system.activationScripts."hermes-agent-config" = lib.stringAfter [ "users" ] ''
      mkdir -p ${hermesHome} ${cfg.workingDirectory}
      chown hermes:hermes ${cfg.stateDir} ${hermesHome} ${cfg.workingDirectory}
      chmod 2750 ${cfg.stateDir} ${hermesHome} ${cfg.workingDirectory}

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
    ];

    users.users =
      (lib.genAttrs cfg.hostUsers (_: {
        extraGroups = [ "hermes" ];
      }))
      // {
        hermes = {
          isSystemUser = true;
          group = "hermes";
          home = cfg.stateDir;
          homeMode = "2750";
          createHome = true;
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
