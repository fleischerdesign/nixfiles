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

  # The workstation onboards the roaming phone clients: it renders their WireGuard configuration from
  # the topology and its own SOPS access, so the private key never has to be copied by hand. Scan it
  # from the rendered file (see docs/operations.md).
  my.features.system.networking.wireguard.clientConfigs = [ "mob-ph-01" ];

  # Features
  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;
  my.features.desktop.niri.enable = true;

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
