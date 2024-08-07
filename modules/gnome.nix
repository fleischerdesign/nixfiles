{ pkgs, ... }:
{
  # Enable the X11 windowing system and desktop environment
  services.xserver.enable = true;
  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
  };
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "de";

# Exclude unnecessary GNOME packages, maintain essential ones
  environment.gnome.excludePackages = (with pkgs; [
    gnome-photos
    gnome-tour
    cheese
    gnome-terminal
    gnome-user-docs
    gnome-text-editor
    gedit
    epiphany
    geary
    totem
    gnome-calendar
  ]) ++ (with pkgs.gnome; [
    gnome-music
    tali # poker game
    iagno # go game
    hitori # sudoku game
    atomix # puzzle game
    gnome-weather
    gnome-maps
    gnome-clocks
  ]);

  services.xserver.excludePackages = [ pkgs.xterm ];

  # Enable KDE Connect with GSConnect package
    programs.kdeconnect.enable = true;
    programs.kdeconnect.package = pkgs.gnomeExtensions.gsconnect;

  # Enable Weylus screenshare
  programs.weylus = {
    enable = true;
    openFirewall = true;
  };
}