# features/desktop/noctalia/nixos.nix - register the per-user shell feature.
{ lib, ... }:
{
  imports = [
    # The login screen is the system half: it runs before any session exists.
    ./greeter.nix
  ];

  options.my.features.desktop.noctalia.enable = lib.mkEnableOption "Noctalia Wayland shell";

  # The shell is not a session and never registers with my.desktop.environments.
  config.home-manager.sharedModules = [ ./home.nix ];
}
