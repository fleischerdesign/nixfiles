{ config, lib, pkgs, ... }:
{
  options.my.nixos.desktop.gnome.enable = lib.mkEnableOption "GNOME desktop environment";

  config = lib.mkIf config.my.nixos.desktop.gnome.enable {
    # Enable the X11 windowing system and desktop environment
    services.xserver.enable = true;
    services.displayManager.gdm = {
      enable = true;
      wayland = true;
    };
    services.desktopManager.gnome.enable = true;

    # Configure keymap in X11
    services.xserver.xkb.layout = "de";

    services.gnome.gnome-keyring.enable = true;
    services.gnome.gnome-online-accounts.enable = true;

    # Exclude unnecessary GNOME packages, maintain essential ones
    environment.gnome.excludePackages = (
      with pkgs;
      [
        #gnome-photos
        gnome-tour
        cheese
        gnome-terminal
        gnome-user-docs
        gnome-text-editor
        gedit
        epiphany
        geary
        totem
        #gnome-calendar
        gnome-music
        tali
        iagno
        hitori
        atomix
        gnome-weather
        gnome-maps
        gnome-clocks
      ]
    );

    services.xserver.excludePackages = [ pkgs.xterm ];

    # Enable KDE Connect with GSConnect package
    programs.kdeconnect.enable = true;
    programs.kdeconnect.package = pkgs.gnomeExtensions.gsconnect;
  };
}