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
      ]);

    inherit (pkgs) nodejs_22;
  };

  configJson = builtins.toJSON (
    lib.recursiveUpdate {
      terminal.cwd = cfg.workingDirectory;
    } config.services.hermes-agent.settings
  );

  generatedConfigFile = pkgs.writeText "hermes-config.yaml" configJson;

  baseDomain = config.my.features.services.caddy.baseDomain or "rls.ancoris.ovh";
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
      subdomainDelegation = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Wildcard subdomain delegation via Caddy.";
      };
      hassUrl = lib.mkOption {
        type = lib.types.str;
        default =
          if
            config.my.endpoints ? home-assistant && config.my.endpoints.home-assistant.proxy.subdomain != null
          then
            "https://${config.my.endpoints.home-assistant.proxy.subdomain}.${
              config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"
            }"
          else
            "https://hass.fls.ancoris.ovh";
        description = "Home Assistant URL.";
      };
      paperlessUrl = lib.mkOption {
        type = lib.types.str;
        default =
          if config.my.endpoints ? paperless && config.my.endpoints.paperless.proxy.subdomain != null then
            "https://${config.my.endpoints.paperless.proxy.subdomain}.${
              config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"
            }"
          else
            "https://paperless.fls.ancoris.ovh";
        description = "Paperless URL.";
      };
      telegramChatId = lib.mkOption {
        type = lib.types.str;
        default = "5838211825";
        description = "Telegram Chat ID for home_channel.";
      };
      workingDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/hermes/workspace";
        description = "Working directory for the hermes-agent service and terminal.cwd setting.";
      };
      camofoxUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9377";
        description = "Camofox browser URL.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      camofox_api_key.restartUnits = lib.mkDefault [ "hermes-agent.service" ];
      hermes_agent_env = {
        owner = "hermes";
        restartUnits = [ "hermes-agent.service" ];
      };
    };

    services.hermes-agent = {
      settings = {
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
        platforms = {
          telegram.home_channel = {
            platform = "telegram";
            chat_id = cfg.telegramChatId;
          };
          webhook = {
            enabled = cfg.subdomainDelegation;
            extra = {
              port = 8644;
              host = "127.0.0.1";
            };
          };
        };
        terminal.backend = "local";
        browser.camofox.managed_persistence = true;
      };
      environmentFiles = [ config.sops.secrets.hermes_agent_env.path ];
      environment = {
        MNEMOSYNE_EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2";
        HASS_URL = cfg.hassUrl;
        PAPERLESS_URL = cfg.paperlessUrl;
        CAMOFOX_URL = cfg.camofoxUrl;
        CAMOFOX_API_KEY = config.sops.placeholder.camofox_api_key;
      };
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
        ExecStart = "${corePackage}/bin/hermes-agent gateway ${lib.escapeShellArgs config.services.hermes-agent.extraArgs}";
        Restart = "always";
        RestartSec = 5;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") config.services.hermes-agent.environment;
        EnvironmentFile = map builtins.toString config.services.hermes-agent.environmentFiles;
        WorkingDirectory = cfg.workingDirectory;
      };

      path = config.services.hermes-agent.extraPackages;
    };

    environment.systemPackages = [ corePackage ];
    environment.variables.HERMES_HOME = "/var/lib/hermes/.hermes";

    system.activationScripts."hermes-agent-config" = lib.stringAfter [ "users" ] ''
      mkdir -p /var/lib/hermes/.hermes ${cfg.workingDirectory}
      chown hermes:hermes /var/lib/hermes /var/lib/hermes/.hermes ${cfg.workingDirectory}
      chmod 2750 /var/lib/hermes /var/lib/hermes/.hermes ${cfg.workingDirectory}

      if [ ! -f /var/lib/hermes/.hermes/config.yaml ]; then
        install -o hermes -g hermes -m 0640 ${generatedConfigFile} /var/lib/hermes/.hermes/config.yaml
      fi
    '';

    systemd.tmpfiles.rules = [
      "d /var/lib/hermes            2770 hermes hermes - -"
      "d /var/lib/hermes/.hermes    2770 hermes hermes - -"
      "d ${cfg.workingDirectory}    2770 hermes hermes - -"
      "d /var/lib/hermes/.gemini    0770 hermes hermes -"
      "d /var/lib/hermes/.config    0770 hermes hermes -"
      "d /var/lib/hermes/.config/gh 0770 hermes hermes -"
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
          home = "/var/lib/hermes";
          homeMode = "2750";
          createHome = true;
        };
      };

    users.groups.hermes = { };

    # ---- Subdomain delegation --------------------------------
    services.caddy.package = lib.mkIf cfg.subdomainDelegation (
      pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-7GoH8YLCoPmPExQxoga2FHB58zQDoZVf1BBwkVi0SsQ=";
      }
    );

    sops.secrets.cloudflare_api_token = lib.mkIf cfg.subdomainDelegation { };

    sops.templates.caddy_env.content = lib.mkIf cfg.subdomainDelegation ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare_api_token}
    '';

    services.caddy.environmentFile = lib.mkIf cfg.subdomainDelegation config.sops.templates.caddy_env.path;

    services.caddy.virtualHosts."*.moebius.${baseDomain}" = lib.mkIf cfg.subdomainDelegation {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        @moebius host *.moebius.${baseDomain}
        handle @moebius {
          reverse_proxy 127.0.0.1:4480
        }
      '';
    };

    systemd.services.hermes-agent-caddy = lib.mkIf cfg.subdomainDelegation {
      description = "Caddy for Hermes Agent Subdomain Delegation";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.caddy}/bin/caddy run --config /var/lib/hermes/.hermes/caddy/Caddyfile --adapter caddyfile";
        ExecReload = "${pkgs.caddy}/bin/caddy reload --config /var/lib/hermes/.hermes/caddy/Caddyfile --address localhost:2020";
        User = "hermes";
        Group = "hermes";
        Restart = "always";
        WorkingDirectory = "/var/lib/hermes";
      };
    };

    systemd.services.hermes-agent-moebius-bootstrap = lib.mkIf cfg.subdomainDelegation {
      description = "Bootstrap Caddy for Moebius subdomain routing";
      wantedBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent-caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        User = "hermes";
        Group = "hermes";
      };
      script = ''
        mkdir -p /var/lib/hermes/.hermes/caddy/routes

        cat > /var/lib/hermes/.hermes/caddy/Caddyfile << 'CADDYEOF'
        {
          admin localhost:2020
          auto_https off
        }

        :4480 {
          import /var/lib/hermes/.hermes/caddy/routes/*
        }
        CADDYEOF

        cat > /var/lib/hermes/.hermes/caddy/routes/webhook << ROUTEEOF
        @webhook host webhook.moebius.${baseDomain}
        handle @webhook {
          rewrite * /webhooks{path}
          reverse_proxy 127.0.0.1:8644 {
            transport http
          }
        }
        ROUTEEOF

        cat > /var/lib/hermes/.hermes/caddy/routes/health << ROUTEEOF
        @health host health.moebius.${baseDomain}
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
