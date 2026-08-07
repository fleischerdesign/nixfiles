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

  networking.hostName = "yorke";

  # Features
  my.features.desktop.niri.enable = true;

  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;

  my.features.media.gaming.sunshine.enable = false;
  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  my.features.dev.opencode = {
    enable = true;
    providers = {
      deepseek.apiKey = config.sops.placeholder."opencode/deepseek";
      openrouter.apiKey = config.sops.placeholder."opencode/openrouter";
    };
  };

  sops.secrets."opencode/deepseek" = { };
  sops.secrets."opencode/openrouter" = { };

  system.stateVersion = "24.05";
}
