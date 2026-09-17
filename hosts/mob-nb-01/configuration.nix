{
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/notebook.nix
  ];

  networking.hostName = "mob-nb-01";

  # Features
  my.features.desktop.niri.enable = true;

  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;

  my.features.media.gaming.sunshine.enable = false;
  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.services.openclaw.node = {
    enable = true;
    rebuild.enable = true;
    instances = {
      philipp = {
        enable = true;
        displayName = "mob-nb-01";
        gateway = {
          host = config.my.features.system.networking.topology.hosts.cld-ops-01.tailscaleIp;
          port = 18789;
        };
        transport = "loopback-tunnel";
        tunnel.localPort = 18790;
        passwordSecret = "openclaw_gateway_password";
        sessionHosting.enable = true;
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
      deepseek.apiKey = config.sops.placeholder."pi/deepseek";
      openrouter.apiKey = config.sops.placeholder."pi/openrouter";
    };
  };

  sops.secrets."pi/deepseek" = { };
  sops.secrets."pi/openrouter" = { };

  system.stateVersion = "24.05";
}
