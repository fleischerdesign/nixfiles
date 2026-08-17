{
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/desktop.nix
  ];

  networking.hostName = "jello";

  # Features
  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;
  my.features.desktop.niri.enable = true;

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  my.features.dev.pi = {
    enable = true;
    providers = {
      deepseek.apiKey = config.sops.placeholder."pi/deepseek";
      openrouter.apiKey = config.sops.placeholder."pi/openrouter";
    };
  };

  sops.secrets."pi/deepseek" = { };
  sops.secrets."pi/openrouter" = { };

  system.stateVersion = "24.05";
}
