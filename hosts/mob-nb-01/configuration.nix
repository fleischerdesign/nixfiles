{
  config,
  ...
}:
{
  imports = [
    # ./disk-config.nix  # Inactive: Enable when bootstrapping/reinstalling with Disko
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

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  my.features.dev.pi = {
    enable = true;
    provider = "opencode-go";
    defaultModel = "deepseek-v4.1-flash";
    providers = {
      deepseek.apiKey = config.sops.placeholder."ai/deepseek_api_key";
      openrouter.apiKey = config.sops.placeholder."ai/openrouter_api_key";
      opencode.apiKey = config.sops.placeholder."ai/opencode_api_key";
      opencode-go.apiKey = config.sops.placeholder."ai/opencode_api_key";
    };
  };

  sops.secrets."ai/deepseek_api_key" = { };
  sops.secrets."ai/openrouter_api_key" = { };
  sops.secrets."ai/opencode_api_key" = { };

  system.stateVersion = "24.05";
}
