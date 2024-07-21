{ config, pkgs, inputs, ... }:

{
  imports =
    [ ./hardware-configuration.nix
      ../default.nix
    ];

  # Define the hosstname
  networking.hostName = "yorke";

  # Enable the X11 windowing system and desktop environment
  services.xserver.enable = true;
  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
  };
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "de";
  # Enable CUPS to print documents
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # Uncomment below for JACK applications
    # jack.enable = true;
  };

  # Home Manager settings
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.philipp = inputs.self.hmModules.philipp;

  # Define the user account
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [ "networkmanager" "wheel" "adbusers"];
  };

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

  # State version setting
  system.stateVersion = "24.05"; # Keep this to match your initial install
}

