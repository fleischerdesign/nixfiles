# roles/server.nix
# This role defines the default features for a headless server.
{
  config,
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
    static.enable = lib.mkDefault true;
  };

  my.features.dev.nixvim.enable = lib.mkDefault true;

  # A server may host the coding workspace, but not every server should: the shape waits here with
  # the master switch off, so turning one on stays a single flag on that host. The credentials are
  # the fleet's own declaration, and the operator owns the files the launcher reads.
  my.features.dev.opencode = {
    enable = lib.mkDefault false;
    # The gateway this fleet uses (OpenCode Go, https://opencode.ai/zen/go/v1) offers
    # deepseek-v4-pro and deepseek-v4.1-flash; a model id it does not offer is a broken default,
    # not a preference (measured: opencode models lists 482 ids and no deepseek-v4-flash).
    model = lib.mkDefault "opencode-go/deepseek-v4.1-flash";
    credentialFiles = config.my.user.aiCredentialFiles;
  };
  my.features.dev.openchamber = {
    enable = lib.mkDefault false;
    web.enable = lib.mkDefault true;
    server.enable = lib.mkDefault true;
  };
}
