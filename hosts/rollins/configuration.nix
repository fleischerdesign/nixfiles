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
      vision.provider = "openrouter";
      vision.model = "xiaomi/mimo-v2.5";
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

  my.features.services.camofox.enable = true;

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
