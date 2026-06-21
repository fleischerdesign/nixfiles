# features/services/hermes-agent/default.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.my.features.services.hermes-agent;

  # Extract mnemosyne bootstrap script so it can be hashed for restartTriggers.
  # When the script changes, NixOS re-runs the oneshot on switch-to-configuration.
  mnemosyneBootstrapScript = ''
    for i in $(seq 1 30); do
      if docker inspect hermes-agent --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
        break
      fi
      sleep 2
    done

    NEEDS_RESTART=false
    if ! docker exec hermes-agent /home/hermes/.venv/bin/python -c "import fastembed" 2>/dev/null; then
      NEEDS_RESTART=true
    fi

    docker exec hermes-agent \
      /home/hermes/.venv/bin/pip install -q mnemosyne-hermes "mnemosyne-memory[embeddings]" ddgs aiohttp
    docker exec hermes-agent \
      /home/hermes/.venv/bin/mnemosyne-hermes --hermes-home /data/.hermes install --force

    if [ "$NEEDS_RESTART" = "true" ]; then
      sleep 3
      systemctl restart --no-block hermes-agent.service
    fi
  '';
in {
  options.my.features.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent";
    model = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-v4-pro";
      description = "Default model for Hermes Agent.";
    };
    hostUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Interactive host users who should have access to the hermes group.";
    };
    subdomainDelegation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable subdomain delegation (*.moebius → Hermes container Caddy)";
    };
    hassUrl = lib.mkOption {
      type = lib.types.str;
      default =
        if config.my.endpoints ? home-assistant && config.my.endpoints.home-assistant.subdomain != null
        then "https://${config.my.endpoints.home-assistant.subdomain}.${config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"}"
        else "https://hass.fls.ancoris.ovh";
      description = "Home Assistant connection URL.";
    };
    paperlessUrl = lib.mkOption {
      type = lib.types.str;
      default =
        if config.my.endpoints ? paperless && config.my.endpoints.paperless.subdomain != null
        then "https://${config.my.endpoints.paperless.subdomain}.${config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"}"
        else "https://paperless.fls.ancoris.ovh";
      description = "Paperless connection URL.";
    };
    telegramChatId = lib.mkOption {
      type = lib.types.str;
      default = "5838211825";
      description = "Telegram Chat ID to inject into configuration updates.";
    };
    camofoxUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9377";
      description = "Camofox anti-detection browser local URL.";
    };
  };

  imports = [
    inputs.hermes-agent.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      extraDependencyGroups = ["messaging"];
      container.extraVolumes = ["/var/lib/camofox:/var/lib/camofox:ro"];
      container.extraOptions =
        [
          "--env"
          "UMASK=0007"
          "--env"
          "PYTHONPATH=/home/hermes/.venv/lib/python3.12/site-packages"
        ]
        ++ lib.optionals cfg.subdomainDelegation [
          "--publish"
          "127.0.0.1:4480:4480"
        ];
      environment = {
        MNEMOSYNE_EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2";
        HASS_URL = cfg.hassUrl;
        PAPERLESS_URL = cfg.paperlessUrl;
        CAMOFOX_URL = cfg.camofoxUrl;
      };
      settings = {
        approvals = {
          mode = "smart";
        };
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
        platforms.webhook = {
          enabled = cfg.subdomainDelegation;
          extra.port = 8644;
          extra.host = "127.0.0.1";
        };
      };
      environmentFiles = [config.sops.secrets.hermes_agent_env.path];
    };

    # Secret environment file containing API keys like OPENROUTER_API_KEY
    sops.secrets.hermes_agent_env = {
      owner = "hermes";
      restartUnits = ["hermes-agent.service"];
    };

    # Moebius subdomain delegation — wildcard TLS via Cloudflare DNS challenge
    services.caddy.package = lib.mkIf cfg.subdomainDelegation (
      pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
        hash = "sha256-8yZDrejNKsaUnUaTUFYbarWNmxafqp2z2rWo+XRsxV8=";
      }
    );

    sops.secrets.cloudflare_api_token = lib.mkIf cfg.subdomainDelegation {};

    sops.templates.caddy_env.content = lib.mkIf cfg.subdomainDelegation ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare_api_token}
    '';

    services.caddy.environmentFile = lib.mkIf cfg.subdomainDelegation config.sops.templates.caddy_env.path;

    services.caddy.virtualHosts."*.moebius.${config.my.features.services.caddy.baseDomain}" =
      lib.mkIf cfg.subdomainDelegation
      {
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }
          @moebius host *.moebius.${config.my.features.services.caddy.baseDomain}
          handle @moebius {
            reverse_proxy 127.0.0.1:4480
          }
        '';
      };

    # Bootstrap Mnemosyne memory provider inside the container
    systemd.services.hermes-agent-mnemosyne-bootstrap = {
      description = "Bootstrap Mnemosyne memory provider inside Hermes container";
      wantedBy = ["hermes-agent.service"];
      after = ["hermes-agent.service"];
      requires = ["hermes-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        User = "root";
      };
      path = with pkgs; [
        docker
        systemd
      ];
      script = mnemosyneBootstrapScript;
      restartTriggers = [
        (builtins.hashString "sha256" mnemosyneBootstrapScript)
      ];
    };

    # Fix permissions and migrate config after upstream activation
    system.activationScripts."hermes-agent-fix-perms" = lib.stringAfter ["hermes-agent-setup"] ''
      # TODO: remove when upstream hermes-agent handles legacy string home_channel format
      ${pkgs.python3.withPackages (ps: [ps.pyyaml])}/bin/python3 << 'PYEOF'
      import yaml
      path = "/var/lib/hermes/.hermes/config.yaml"
      try:
          with open(path) as f:
              cfg = yaml.safe_load(f)
      except Exception:
          raise SystemExit(0)
      changed = False
      nc = {"platform": "telegram", "chat_id": "${cfg.telegramChatId}"}
      for section in ("telegram",):
          if section in cfg and isinstance(cfg[section], dict):
              hc = cfg[section].get("home_channel")
              if isinstance(hc, str):
                  cfg[section]["home_channel"] = nc
                  changed = True
      if "platforms" in cfg and isinstance(cfg.get("platforms"), dict):
          p = cfg["platforms"].get("telegram")
          if isinstance(p, dict) and isinstance(p.get("home_channel"), str):
              p["home_channel"] = nc
              changed = True
      # Persistent Camofox browser sessions
      if not cfg.get("browser", {}).get("camofox", {}).get("managed_persistence"):
          cfg.setdefault("browser", {}).setdefault("camofox", {})["managed_persistence"] = True
          changed = True
      if changed:
          with open(path, "w") as f:
              yaml.safe_dump(cfg, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
      PYEOF

      chmod 0640 /var/lib/hermes/.hermes/.env
      chmod 2750 /var/lib/hermes/.hermes
      find /var/lib/hermes/.hermes -type d ! -perm /g=rx -exec chmod g+rx {} \; 2>/dev/null || true
      find /var/lib/hermes/.hermes -type f ! -perm /g=r -exec chmod g+r {} \; 2>/dev/null || true
    '';

    # Moebius — container Caddy bootstrap (install + start)
    systemd.services.hermes-agent-moebius-bootstrap = lib.mkIf cfg.subdomainDelegation {
      description = "Bootstrap Caddy inside Hermes container for Moebius subdomain routing";
      wantedBy = ["hermes-agent.service"];
      after = ["hermes-agent.service"];
      requires = ["hermes-agent.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        User = "root";
      };
      path = with pkgs; [docker];
      script = ''
          # Wait for container
          for i in $(seq 1 30); do
            if docker inspect hermes-agent --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
              break
            fi
            sleep 2
          done

          # Install Caddy inside container (copy Nix-built binary)
          docker cp ${pkgs.caddy}/bin/caddy hermes-agent:/usr/local/bin/caddy 2>/dev/null || true

          # Write/update Caddyfile
          docker exec hermes-agent mkdir -p /data/.hermes/caddy
          docker exec hermes-agent sh -c 'cat > /data/.hermes/caddy/Caddyfile << "CADDYEOF"
          {
            admin localhost:2020
            auto_https off
          }

          :4480 {
            import /data/.hermes/caddy/routes/*
          }
        CADDYEOF'

          # Start Caddy in background inside container
          docker exec -d hermes-agent caddy run --config /data/.hermes/caddy/Caddyfile --adapter caddyfile 2>/dev/null || true

          # Create/update webhook route
          docker exec hermes-agent mkdir -p /data/.hermes/caddy/routes
          docker exec hermes-agent sh -c 'cat > /data/.hermes/caddy/routes/webhook << ROUTEEOF
        @webhook host webhook.moebius.${config.my.features.services.caddy.baseDomain}
        handle @webhook {
          rewrite * /webhooks{path}
          reverse_proxy 127.0.0.1:8644 {
            transport http
          }
        }
        ROUTEEOF'
          docker exec hermes-agent caddy reload --config /data/.hermes/caddy/Caddyfile --address localhost:2020 2>/dev/null || true

          # Run container bootstrap scripts (user-managed, survives rebuilds)
          docker exec -d hermes-agent sh -c '
            if [ -d /data/.hermes/bootstrap ]; then
              for script in /data/.hermes/bootstrap/*; do
                [ -f "$script" ] && [ -x "$script" ] && "$script" &
              done
            fi
          '
      '';
    };

    # Dynamically add all configured host users to the hermes and docker groups
    users.users =
      (lib.genAttrs cfg.hostUsers (_user: {
        extraGroups = [
          "hermes"
          "docker"
        ];
      }))
      // {
        hermes = {
          homeMode = "2750";
        };
      };
  };
}
