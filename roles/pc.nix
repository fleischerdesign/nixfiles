# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{
  config,
  lib,
  ...
}:
{
  imports = [
    ./base.nix
  ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  my.user.extraGroups = lib.mkDefault [
    "networkmanager"
    "wheel"
    "adbusers"
    "input"
    "uinput"
  ];

  my.user.profiles = lib.mkDefault [
    "core"
    "graphical"
  ];

  # It enables a baseline set of features common to all graphical systems.
  my.features.system = {
    audio.enable = lib.mkDefault true;
    wayland.enable = lib.mkDefault true;
    printing.enable = lib.mkDefault true;
    locate.enable = lib.mkDefault true;
    rclone.enable = lib.mkDefault true;
  };

  my.features.desktop = {
    chatgpt.enable = lib.mkDefault true;
    webapps.enable = lib.mkDefault true;
    # Every personal computer runs the same graphical session: Niri with the Noctalia shell.
    # A host may override it, but the default is the session, not a per-host copy.
    niri.enable = lib.mkDefault true;
    noctalia.enable = lib.mkDefault true;
  };

  # The shell's Phone Operate plugin talks to KDE Connect, so the daemon and its ports are a
  # prerequisite of the session on every personal computer, not of one host.
  programs.kdeconnect.enable = lib.mkDefault true;

  my.features.dev = {
    codex.enable = lib.mkDefault true;
    opencodex = {
      enable = lib.mkDefault true;
      credentialFiles = config.my.user.aiCredentialFiles;
    };
    containers.enable = lib.mkDefault true;
    codium.enable = lib.mkDefault true;
    nixvim.enable = lib.mkDefault true;
    obsidian.enable = lib.mkDefault true;
    # Every personal computer carries the coding workspace: OpenCode, with the OpenChamber web and
    # desktop interfaces on top of it. The credentials come from the one fleet declaration, and each
    # computer serves its own instance over the mesh so the other one is reachable from it. A host
    # may turn a master switch off; nothing else has to be remembered.
    opencode = {
      enable = lib.mkDefault true;
      # The gateway this fleet uses (OpenCode Go, https://opencode.ai/zen/go/v1) offers
      # deepseek-v4-pro and deepseek-v4.1-flash; a model id it does not offer is a broken default,
      # not a preference (measured: opencode models lists 482 ids and no deepseek-v4-flash).
      model = lib.mkDefault "opencode-go/deepseek-v4.1-flash";
      credentialFiles = config.my.user.aiCredentialFiles;
    };
    openchamber = {
      enable = lib.mkDefault true;
      web.enable = lib.mkDefault true;
      desktop.enable = lib.mkDefault true;
      # A personal computer runs its instance when you work on it (the web and desktop surfaces
      # above), and you pair your devices with that running instance - a pairing link is exactly
      # what the settings dialog mints. A second, always-on API-only unit next to it would target the
      # same data directory and the same default port, so it is an explicit choice, not a default;
      # the always-on instance belongs on the machine that never sleeps. A reachable bind needs a UI
      # password (openchamber/ui_password) either way.
      server.enable = lib.mkDefault false;
    };
  };

  my.features.media = {
    gaming.enable = lib.mkDefault true;
    spotify.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";
}
