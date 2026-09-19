# roles/desktop.nix
# This role defines the default features for a stationary desktop PC.
{ lib, ... }:

{
  imports = [
    ./pc.nix # Inherit common PC features
  ];

  my.role = "desktop";

  # A stationary desktop is a fixed member of its zone, so it takes its address from the topology
  # instead of from DHCP. The notebook role deliberately does not do this - it roams. Without this
  # the topology's `interface` field stays unused and the host keeps a lease from whatever DHCP
  # server happens to answer.
  my.features.system.networking.static.enable = lib.mkDefault true;
}
