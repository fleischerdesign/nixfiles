# features/services/hermes-agent/default.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.services.hermes-agent;

  # Define custom Python packages since they are not in nixpkgs
  pythonPackages = pkgs.python312Packages;

  ddgs = pythonPackages.buildPythonPackage rec {
    pname = "ddgs";
    version = "9.14.4";
    src = pythonPackages.fetchPypi {
      inherit pname version;
      sha256 = "f7b118a2b709a9e9c04a1dca6e96b98c25d4dfaca1a4b0a244d74454fcca48ef";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = with pythonPackages; [
      click
      primp
      lxml
      httpx
      fake-useragent
    ];
    doCheck = false;
  };

  # Override fastembed from nixpkgs to remove pillow, avoiding collisions with hermes core venv
  fastembed-override = pythonPackages.fastembed.overridePythonAttrs (oldAttrs: {
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ ];
    propagatedBuildInputs = lib.filter (p:
      let pname = p.pname or "";
      in pname != "pillow" && pname != "Pillow"
    ) (oldAttrs.propagatedBuildInputs or [ ]);
    dependencies = lib.filter (p:
      let pname = p.pname or "";
      in pname != "pillow" && pname != "Pillow"
    ) (oldAttrs.dependencies or [ ]);
  });

  mnemosyne-memory = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-memory";
    version = "3.8.0";
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_memory";
      inherit version;
      sha256 = "c4de8fe8761df206b09d4d9b1595e8cf28a89e925e68b4d3340181b80851ac66";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = with pythonPackages; [
      sqlite-vec
      fastembed-override
      numpy
    ];
    doCheck = false;
  };

  mnemosyne-hermes = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-hermes";
    version = "0.2.0";
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_hermes";
      inherit version;
      sha256 = "896946bda8cc420fc613c55d27b553340cf120b44d5084b4d3f02b6060e585b3";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = [
      mnemosyne-memory
    ];
    doCheck = false;
  };
in
{
  options.my.features.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent";
    model = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-v4-flash";
      description = "Default model for Hermes Agent.";
    };
    hostUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
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
        if config.my.endpoints ? home-assistant && config.my.endpoints.home-assistant.subdomain != null then
          "https://${config.my.endpoints.home-assistant.subdomain}.${
            config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"
          }"
        else
          "https://hass.fls.ancoris.ovh";
      description = "Home Assistant connection URL.";
    };
    paperlessUrl = lib.mkOption {
      type = lib.types.str;
      default =
        if config.my.endpoints ? paperless && config.my.endpoints.paperless.subdomain != null then
          "https://${config.my.endpoints.paperless.subdomain}.${
            config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"
          }"
        else
          "https://paperless.fls.ancoris.ovh";
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
      package = pkgs.hermes-agent;
      addToSystemPackages = true;
      extraDependencyGroups = [ "messaging" ];
      
      # Add native Python packages to PYTHONPATH
      extraPythonPackages = [
        mnemosyne-hermes
        mnemosyne-memory
        ddgs
      ];

      # Add Nix and tooling to the systemd path so nix-shell is usable
      extraPackages = with pkgs; [
        nix
        gh
        antigravity-cli
      ];

      # Env vars
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
        terminal = {
          backend = "local";
        };
      };
      environmentFiles = [ config.sops.secrets.hermes_agent_env.path ];
    };

    # Secret environment file containing API keys like OPENROUTER_API_KEY
    sops.secrets.hermes_agent_env = {
      owner = "hermes";
      restartUnits = [ "hermes-agent.service" ];
    };

    # Moebius subdomain delegation — wildcard TLS via Cloudflare DNS challenge
    services.caddy.package = lib.mkIf cfg.subdomainDelegation (
      pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-hEHgAG0F0ozHRAPuxEqLyTATBrE+pajeXDiSNwniorg=";
      }
    );

    sops.secrets.cloudflare_api_token = lib.mkIf cfg.subdomainDelegation { };

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

    # Oneshot service to bootstrap Mnemosyne database natively on the host
    systemd.services.hermes-agent-mnemosyne-bootstrap = {
      description = "Bootstrap Mnemosyne memory provider natively";
      wantedBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "hermes";
        Group = "hermes";
        ExecStart = "${mnemosyne-hermes}/bin/mnemosyne-hermes --hermes-home /var/lib/hermes/.hermes install --force";
      };
    };

    # Fix permissions and migrate config after upstream activation
    system.activationScripts."hermes-agent-fix-perms" = lib.stringAfter [ "hermes-agent-setup" ] ''
      # TODO: remove when upstream hermes-agent handles legacy string home_channel format
      ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 << 'PYEOF'
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

    # Native Caddy service for subdomain delegation (replaces container Caddy)
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

    # Rewrite bootstrap script to generate Caddy Caddyfile on host
    systemd.services.hermes-agent-moebius-bootstrap = lib.mkIf cfg.subdomainDelegation {
      description = "Bootstrap Caddy natively for Moebius subdomain routing";
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
        
        # Write Caddyfile
        cat > /var/lib/hermes/.hermes/caddy/Caddyfile << "CADDYEOF"
        {
          admin localhost:2020
          auto_https off
        }

        :4480 {
          import /var/lib/hermes/.hermes/caddy/routes/*
        }
        CADDYEOF

        # Write webhook route
        cat > /var/lib/hermes/.hermes/caddy/routes/webhook << ROUTEEOF
        @webhook host webhook.moebius.${config.my.features.services.caddy.baseDomain}
        handle @webhook {
          rewrite * /webhooks{path}
          reverse_proxy 127.0.0.1:8644 {
            transport http
          }
        }
        ROUTEEOF

        # Write health route
        cat > /var/lib/hermes/.hermes/caddy/routes/health << ROUTEEOF
        @health host health.moebius.${config.my.features.services.caddy.baseDomain}
        handle @health {
          reverse_proxy 127.0.0.1:8090 {
            transport http
          }
        }
        ROUTEEOF

        systemctl reload hermes-agent-caddy.service 2>/dev/null || true
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/hermes/.gemini 0770 hermes hermes -"
      "d /var/lib/hermes/.config 0770 hermes hermes -"
      "d /var/lib/hermes/.config/gh 0770 hermes hermes -"
      "f /var/lib/systemd/linger/hermes 0644 root root - -"
    ];

    # Dynamically add all configured host users to the hermes group
    users.users =
      (lib.genAttrs cfg.hostUsers (user: {
        extraGroups = [
          "hermes"
        ];
      }))
      // {
        hermes = {
          homeMode = "2750";
        };
      };
  };
}
