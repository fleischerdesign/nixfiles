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
