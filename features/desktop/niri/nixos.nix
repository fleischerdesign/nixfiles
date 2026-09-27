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
  imports = [
    inputs.niri.nixosModules.niri
    inputs.axis.nixosModules.default
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
    # Dependencies
    my.features.system.wayland.enable = true;
    my.features.system.audio.enable = true;

    # Conflicts
    assertions = [
      {
        assertion = !config.my.features.desktop.gnome.enable;
        message = "Niri cannot be enabled alongside Gnome.";
      }
    ];

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
