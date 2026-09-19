# roles/server.nix
# This role defines the default features for a headless server.
{
  lib,
  ...
}:
{
  imports = [
    ./base.nix
  ];

  my.role = "server";

  # A server has no interactive local accounts besides the operator, whose password is declared in
  # the secret store. Enforcing it puts every server on the same password instead of whatever was
  # set when the machine was installed: with the default `mutableUsers = true` the declaration is
  # applied when the account is created and never again - which is exactly how one host ended up
  # with a password that matched neither the declared hash nor any other host.
  #
  # Workstations deliberately keep mutable users: family members have local accounts there whose
  # passwords are not, and should not be, part of the secret store.
  users.mutableUsers = false;

  my.features.services = {
    caddy.enable = lib.mkDefault true;
  };

  my.features.services.monitoring = {
    node-exporter.enable = lib.mkDefault true;
    blackbox-exporter.enable = lib.mkDefault true;
  };

  my.features.system.networking = {
    tailscale.enable = lib.mkDefault true;
    static.enable = lib.mkDefault true;
  };

  my.features.dev.nixvim.enable = lib.mkDefault true;
}
