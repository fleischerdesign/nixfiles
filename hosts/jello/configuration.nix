{
  config,
  pkgs,
  inputs,
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
  my.features.media.gaming.enable = true;
  my.features.media.spotify.enable = true;
  my.features.system.networking.tailscale.enable = true;

  my.features.dev.containers.enable = true;
  my.features.dev.containers.users = [ "philipp" ];
  my.features.dev.android.enable = true;
  my.features.dev.codium.enable = true;
  my.features.dev.nixvim.enable = true;
  my.features.desktop.niri.enable = true;

  system.stateVersion = "24.05";
}
