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
  };

  my.features.desktop = {
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
    containers.enable = lib.mkDefault true;
    codium.enable = lib.mkDefault true;
    nixvim.enable = lib.mkDefault true;
    obsidian.enable = lib.mkDefault true;
    opencode = {
      enable = lib.mkDefault true;
      model = lib.mkDefault "opencode-go/deepseek-v4-flash";
      credentialFiles = {
        DEEPSEEK_API_KEY = config.sops.secrets."ai/deepseek_api_key".path;
        OPENROUTER_API_KEY = config.sops.secrets."ai/openrouter_api_key".path;
        OPENCODE_API_KEY = config.sops.secrets."ai/opencode_api_key".path;
      };
    };
    openchamber = {
      enable = lib.mkDefault true;
      web.enable = lib.mkDefault true;
      desktop.enable = lib.mkDefault true;
    };
  };

  sops.secrets."ai/deepseek_api_key".owner = config.my.user.primary;
  sops.secrets."ai/openrouter_api_key".owner = config.my.user.primary;
  sops.secrets."ai/opencode_api_key".owner = config.my.user.primary;

  my.features.media = {
    gaming.enable = lib.mkDefault true;
    spotify.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";
}
