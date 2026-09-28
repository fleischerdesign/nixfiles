# features/desktop/gnome/nixos.nix - the system half of the GNOME feature.
#
# The GNOME desktop-manager module already pulls in what a GNOME session needs to be usable:
# core-os-services (dconf, Polkit, xdg portals, keyring, power profiles, NetworkManager), core-shell
# (gvfs, GNOME Shell, settings daemon) and core-apps. Verified against the pinned nixpkgs before this
# was written; this file therefore adds only the gaps - GDM itself, the session pinned by name, and
# the site's decision about which core apps not to install.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.gnome;
in
{
  options.my.features.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME desktop environment";

    excludePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        epiphany
        gnome-contacts
        gnome-maps
        gnome-music
        gnome-weather
        showtime
      ];
      example = lib.literalExpression "[ pkgs.epiphany ]";
      description = ''
        GNOME core apps this site does not install, fed verbatim to
        `environment.gnome.excludePackages`. The defaults are apps the fleet already covers
        elsewhere or has no declared use for: Chrome replaces the browser, Google Workspace the
        contacts, and maps/weather/music/video have no consumer. A site decision, not a per-host
        one - override it where the fleet's needs change.
      '';
    };
  };

  config = lib.mkMerge [
    # The Home Manager half is always imported so a user can declare personal GNOME settings on any
    # host; the option defaults to the system switch below, so the settings stay inert where GNOME
    # is not the session. This is the same shape the webapps feature uses.
    {
      home-manager.sharedModules = [ ./home.nix ];
    }

    (lib.mkIf cfg.enable {
      # Register with the desktop contract: this feature *is* the host's session, and the contract's
      # one-session invariant reads that registration (`contracts/desktop/nixos.nix`).
      my.desktop.environments.gnome = true;

      my.features.system.wayland.enable = true;
      my.features.system.audio.enable = true;

      services.desktopManager.gnome.enable = true;

      # The desktop-manager module seeds this line into `nixos-generate-config` but does not enable
      # it: without GDM there is no login screen. GDM is also the supported display manager for
      # GNOME's screen lock (measured against the pinned nixpkgs module).
      services.displayManager.gdm.enable = true;

      # Pin the session by name so an additionally installed session can never be chosen silently.
      services.displayManager.defaultSession = "gnome";

      environment.gnome.excludePackages = cfg.excludePackages;
    })
  ];
}
