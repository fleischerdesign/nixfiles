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

  # Capability-based authorization on the public multi-tenant gateway.
  # Enforcement is default-deny: a tenant may only reach the explicit grants
  # below, keyed on its authenticated IdP groups (agnostic — no hardcoded
  # username/sub). The operator (`group:wheel`) gets the config + tenant store;
  # family/members get bounded read-only media/public roots.
  my.features.dev.dsh.authorization = {
    enable = true;
    pathTools = [
      "read"
      "write"
      "edit"
      "glob"
      "bash"
    ];
    grants = [
      {
        principal = "group:wheel";
        resources = [
          "path:/etc/nixos/**"
          "path:/var/lib/dsh/tenants/**"
        ];
        actions = [
          "read"
          "write"
          "mutate"
          "exec"
        ];
      }
      {
        principal = "group:family";
        resources = [
          "path:/srv/media/**"
          "path:/srv/public/**"
        ];
        actions = [
          "read"
          "list"
        ];
      }
    ];
  };

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

  # dsh-web runs as a persistent SYSTEM daemon on every host (dedicated `dsh`
  # user, DSH_HOME=/var/lib/dsh) — configured once in roles/base.nix. rollins
  # only differentiates its public multi-tenant identity via the OIDC config
  # below (dsh-auth interactive Authorization Code + PKCE).

  # dsh-auth interactive OIDC (Authorization Code + PKCE) against the existing
  # Authentik. clientId + clientSecret (via env) are filled once the Authentik
  # OAuth2/OIDC application for dsh exists.
  my.features.dev.dsh.auth.oidc = {
    enabled = true;
    # Authentik OIDC application slug is "deepseek-harness" (not "dsh").
    issuer = "https://auth.ancoris.ovh/application/o/deepseek-harness/";
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
    # Authentik uses provider-agnostic endpoints (not issuer-slug derived), so
    # we set them explicitly to avoid a discovery race on the first redirect.
    authorizeUrl = "https://auth.ancoris.ovh/application/o/authorize/";
    tokenUrl = "https://auth.ancoris.ovh/application/o/token/";
    jwksUrl = "https://auth.ancoris.ovh/application/o/deepseek-harness/jwks/";
  };

  # Public multi-tenant node: OIDC is the ONLY authentication path. Disable the
  # loopback admin fallback so nothing can be mistaken for a local privileged
  # connection (defense-in-depth; the socket IP behind Caddy is loopback, so
  # the X-Forwarded-For resolution is also enforced by the auth plugin).
  my.features.dev.dsh.auth.loopback.enabled = false;

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
