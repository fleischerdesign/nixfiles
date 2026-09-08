{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "rollins";

  my.features.services.caddy.baseDomain = "rls.ancoris.ovh";

  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.services.monitoring = {
    pipeline = {
      enable = true;
      role = "collector";
    };
  };

  my.features.services.attic.server.enable = true;

  my.features.services.crowdsec = {
    enable = true;
    role = "agent";
    excludeLogPatterns = [
      ".*cache.*"
      ".*moebius.*"
    ];
  };

  my.features.services.hermes = {
    enable = true;
    soulContent = builtins.readFile ../../features/services/hermes/SOUL.md;
    integrations = {
      hass = {
        enable = true;
        url = "https://hass.fls.ancoris.ovh";
      };
      paperless = {
        enable = true;
        url = "https://paperless.fls.ancoris.ovh";
      };
      camofox = {
        enable = true;
        url = "http://127.0.0.1:9377";
      };
      telegram = {
        enable = true;
        chatId = "5838211825";
      };
      vikunja = {
        enable = false;
        url = "https://vikunja.mky.ancoris.ovh";
      };
    };
    subdomainDelegation = {
      enable = true;
      prefix = "moebius";
    };
    extensions = {
      webui.enable = true;
      webui.oidc = {
        clientId = "WLcmhxTlLrbN9R4e7bfnlSNYi387OW1ynQWu27dG";
        issuer = "https://auth.ancoris.ovh/application/o/hermes/";
        allowValues = "philipp@fleischer.design";
      };
      mnemosyne.enable = true;
      ddgs.enable = true;
      obsidian.enable = true;
    };
    auxiliary = {
      vision.provider = "deepseek";
      vision.model = "DeepSeek-V4-Flash-Vision-Exp";
      title_generation.provider = "deepseek";
      title_generation.model = "deepseek-v4-flash";
      compression.provider = "deepseek";
      compression.model = "deepseek-v4-flash";
      approval.provider = "deepseek";
      approval.model = "deepseek-v4-flash";
      web_extract.provider = "deepseek";
      web_extract.model = "deepseek-v4-flash";
    };
  };

  services.hermes-agent.environment = {
    API_SERVER_ENABLED = "true";
    API_SERVER_HOST = "127.0.0.1";
    API_SERVER_PORT = "8642";
  };

  my.endpoints.hermes-webui = {
    proxy = {
      enable = true;
      subdomain = "moebius";
      auth = false;
    };
  };

  # Public dsh (AI) web surface on rollins: ai.rls.ancoris.ovh. Auth is handled
  # NATIVELY by dsh-auth (interactive OIDC), so NO Caddy forward_auth here
  # (auth=false) — the Authentik proxy outpost is not used for dsh.
  my.endpoints.dsh = {
    host = "rollins";
    port = 3080;
    proxy = {
      enable = true;
      subdomain = "ai";
      auth = false;
    };
  };

  # dsh-web on rollins runs as a persistent SYSTEM service (public node),
  # independent of any user session.
  my.features.dev.dsh.web = {
    enable = true;
    systemService = true;
    user = "philipp";
    host = "127.0.0.1";
    port = 3080;
  };

  # dsh-auth interactive OIDC (Authorization Code + PKCE) against the existing
  # Authentik. clientId + clientSecret (via env) are filled once the Authentik
  # OAuth2/OIDC application for dsh exists.
  my.features.dev.dsh.auth.oidc = {
    enabled = true;
    issuer = "https://auth.ancoris.ovh/application/o/dsh/";
    clientId = "BbvVsvWMTO7d1SYewJGbB0rkWTYmWrKtiPeFqImX";
    redirectUri = "https://ai.rls.ancoris.ovh/oidc/callback";
    scopes = [
      "openid"
      "profile"
      "email"
    ];
    adminClaim = "groups";
    adminValues = [
      "authentik Admins"
      "admin"
    ];
    clientSecretEnv = "DHS_OIDC_CLIENT_SECRET";
  };

  my.features.services.camofox.enable = true;

  sops.secrets."pi/deepseek" = { };
  sops.secrets."pi/openrouter" = { };

  sops.secrets.hermes_ssh_key = {
    owner = "hermes";
    mode = "0600";
    path = "/var/lib/hermes/.ssh/id_ed25519";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hermes/.ssh 0700 hermes hermes - -"
  ];

  system.stateVersion = "24.11";
}
