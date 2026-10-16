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
      # A personal computer is reachable from a phone: the headless unit serves the API on the
      # host's mesh address and a device pairs with that instance, while the interface you actually
      # work in keeps its own runtime - OpenChamber addresses runtimes per port and lists several
      # of them side by side (`openchamber status`), so the two do not displace each other. The unit
      # is a user service and lives while the session does, which is when the machine is usable
      # anyway; the machine that never sleeps is the one to pair with for access from anywhere. A
      # reachable bind needs a UI password (openchamber/ui_password) either way.
      server.enable = lib.mkDefault true;
    };
  };

  my.features.media = {
    gaming.enable = lib.mkDefault true;
    spotify.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";
}
