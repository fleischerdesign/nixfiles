# roles/notebook.nix
# This role defines the default features for a notebook PC.
{ lib, ... }:

{
  imports = [
    ./pc.nix # Inherit common PC features
  ];

  my.role = "notebook";

  # Add notebook-specific feature defaults here, e.g.:
  # my.features.power-management.enable = lib.mkDefault true;
  # my.features.touchpad.enable = lib.mkDefault true;
}