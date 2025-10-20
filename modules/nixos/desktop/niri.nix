{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.my.nixos.desktop.niri;
in
{
  imports = [
    inputs.niri.nixosModules.niri
  ];

  config = lib.mkIf cfg.enable {
    # Disable X server for a pure Wayland setup
    services.xserver.enable = false;

    # Configure greetd with tuigreet to launch niri-session
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd '${pkgs.niri}/bin/niri-session'";
        };
      };
    };
    
    programs.niri.enable = true;
    programs.niri.package = pkgs.niri;

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };

    services.upower.enable = true;
  };
}
