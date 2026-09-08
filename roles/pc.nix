# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{ lib, config, ... }: {
  imports = [
    ./base.nix
  ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # The dsh agent may edit the operator's development repositories. The home
  # itself is NOT exposed (the grant walks the ancestor chain as traverse-only
  # and only the dev directory gets rwx) — the logical path-capability layer
  # does the real per-principal gating; this is the durable OS backstop.
  # Merges with roles/base.nix's `agent.workspaces` (the config repo).
  my.features.dev.dsh.agent.workspaces = lib.mkDefault [
    "/home/${config.my.user.name}/dev"
  ];

  my.user.extraGroups = lib.mkDefault [
    "networkmanager"
    "wheel"
    "adbusers"
    "input"
    "uinput"
  ];

  # It enables a baseline set of features common to all graphical systems.
  my.features.system = {
    audio.enable = lib.mkDefault true;
    wayland.enable = lib.mkDefault true;
    printing.enable = lib.mkDefault true;
  };

  my.features.desktop = {
    webapps.enable = lib.mkDefault true;
  };

  my.features.dev = {
    containers.enable = lib.mkDefault true;
    codium.enable = lib.mkDefault true;
    nixvim.enable = lib.mkDefault true;
    obsidian.enable = lib.mkDefault true;
  };

  my.features.media = {
    gaming.enable = lib.mkDefault true;
    spotify.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";
}
