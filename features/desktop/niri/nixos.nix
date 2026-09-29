# features/desktop/niri/nixos.nix - the compositor and its session.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.desktop.niri;
in
{
  imports = [
    inputs.niri.nixosModules.niri
  ];

  options.my.features.desktop.niri = {
    enable = lib.mkEnableOption "Niri desktop environment";
    outputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Niri output configurations (positions, scales, etc.)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register with the desktop contract: this feature *is* the host's session, and the contract's
    # one-session invariant reads that registration (`contracts/desktop/nixos.nix`). No module
    # repeats the mutual-exclusion check.
    my.desktop.environments.niri = true;

    my.features.system.wayland.enable = true;
    my.features.system.audio.enable = true;

    services = {
      xserver.enable = false;
      gvfs.enable = true;
      # This site deliberately starts Niri directly as the primary user. The session
      # command is owned here, not by the optional desktop shell.
      greetd = {
        enable = true;
        settings.default_session = {
          command = "${pkgs.niri}/bin/niri-session";
          user = config.my.user.primary;
        };
      };
      upower.enable = true;
      power-profiles-daemon.enable = true;
      gnome.gnome-keyring.enable = true;
    };

    programs.niri.enable = true;
    programs.niri.package = pkgs.niri;

    xdg.portal = {
      enable = true;
      config.common.default = [ "gnome" ];
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome
      ];
    };

    home-manager.sharedModules = [ ./home.nix ];
  };
}
