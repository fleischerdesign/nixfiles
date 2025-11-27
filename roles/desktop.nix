# roles/desktop.nix
# This role defines the default features for a stationary desktop PC.
{ lib, ... }:

{
  imports = [
    ./pc.nix # Inherit common PC features
  ];

  # Add desktop-specific feature defaults here if any, e.g.:
  # my.features.large-monitor-support.enable = lib.mkDefault true;
}