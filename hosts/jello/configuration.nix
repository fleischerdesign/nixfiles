{
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

  my.features.dev.containers = {
    users = [ "philipp" ];
  };
  my.features.dev.android.enable = true;
  my.features.desktop.niri.enable = true;

  my.features.services.attic.client = {
    enable = true;
    user = "philipp";
    autoPush = true;
  };

  system.stateVersion = "24.05";
}
