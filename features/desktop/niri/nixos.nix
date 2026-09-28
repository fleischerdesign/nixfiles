# features/niri.nix
{
  config,
  lib,
  pkgs,
  hostname,
  inputs,
  ...
}:
let
  cfg = config.my.features.desktop.niri;
in
{
  # Only the Niri flake's module is imported. The Axis flake's module applies its configuration
  # unconditionally - no `mkIf enable` - so importing it made Axis active on hosts that do not run
  # it at all: wl-clipboard installed, mDNS publishing on, TCP 7391 opened. Its system settings are
  # declared below, scoped to this feature, which is the only place they belong. Axis is still used
  # as a package by the user half (`features/desktop/niri/home.nix`).
  imports = [
    inputs.niri.nixosModules.niri
  ];

  options.my.features.desktop.niri = {
    enable = lib.mkEnableOption "Niri desktop environment";
    outputs = lib.mkOption {
      type = lib.types.attrs;
      default =
        if hostname == "hom-wrk-01" then
          {
            "DP-1" = {
              position = {
                x = 320;
                y = 0;
              };
            };
            "HDMI-A-2" = {
              position = {
                x = 0;
                y = 1080;
              };
              focus-at-startup = true;
            };
          }
        else
          { };
      description = "Niri output configurations (positions, scales, etc.)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register with the desktop contract: this feature *is* the host's session, and the contract's
    # one-session invariant reads that registration (`contracts/desktop/nixos.nix`). No module
    # repeats the mutual-exclusion check.
    my.desktop.environments.niri = true;

    # Dependencies
    my.features.system.wayland.enable = true;
    my.features.system.audio.enable = true;

    # System-level configuration for Niri

    # Disable X server for a pure Wayland setup
    services = {
      xserver.enable = false;
      gvfs.enable = true;
      greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.niri}/bin/niri-session";
            user = config.my.user.name;
          };
        };
      };
      upower.enable = true;
      power-profiles-daemon.enable = true;
      gnome.gnome-keyring.enable = true;
      locate = {
        enable = true;
        package = pkgs.plocate;
      };
    };

    programs.niri.enable = true;
    programs.niri.package = pkgs.niri;

    # Axis's system integration, restated here so it is scoped to this feature. Upstream's NixOS
    # module declares exactly this set with no enable guard; importing it applied all of it on hosts
    # that run a different desktop.
    environment.systemPackages = [ pkgs.wl-clipboard ];

    services.udev.extraRules = ''
      KERNEL=="uinput", GROUP="uinput", MODE="0660", OPTIONS+="static_node=uinput"
      KERNEL=="event*", NAME="input/%k", MODE="0660", GROUP="input"
    '';

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ 7391 ];

    xdg.portal = {
      enable = true;
      config.common.default = [ "gnome" ];
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome
      ];
    };

    # Home Manager-level configuration for Niri
    home-manager.sharedModules = [ ./home.nix ];
  };
}
