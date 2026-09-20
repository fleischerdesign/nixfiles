{
  config,
  ...
}:
{
  imports = [
    # ./disk-config.nix  # Inactive: Enable when bootstrapping/reinstalling with Disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/desktop.nix
  ];

  networking.hostName = "hom-wrk-01";

  # Features
  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;
  my.features.desktop.niri.enable = true;

  my.features.services.openclaw.node = {
    enable = true;
    rebuild.enable = true;
    instances = {
      philipp = {
        enable = true;
        displayName = "hom-wrk-01";
        gateway = {
          host = config.my.topology.hosts.cld-ops-01.wireguardIpv4;
          port = 18789;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18790;
        sessionHosting.enable = true;
        browserProxy.enable = true;
      };
    };
  };

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  my.features.dev.pi = {
    enable = true;
    provider = "deepseek";
    defaultModel = "DeepSeek-V4-Flash-Vision-Exp";
    providers = {
      deepseek.apiKey = config.sops.placeholder."ai/deepseek_api_key";
      openrouter.apiKey = config.sops.placeholder."ai/openrouter_api_key";
    };
  };

  sops.secrets."ai/deepseek_api_key" = { };
  sops.secrets."ai/openrouter_api_key" = { };

  system.stateVersion = "24.05";
}
