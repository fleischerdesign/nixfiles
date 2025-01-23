{ pkgs, ... }:
{

nixpkgs.overlays = [
  (final: prev: {
    mutter = prev.mutter.overrideAttrs (oldAttrs: {
      # GNOME dynamic triple buffering (huge performance improvement)
      # See https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1441
      src = final.fetchFromGitLab {
        domain = "gitlab.gnome.org";
        owner = "vanvugt";
        repo = "mutter";
        rev = "triple-buffering-v4-47";
        hash = "sha256-ajxm+EDgLYeqPBPCrgmwP+FxXab1D7y8WKDQdR95wLI=";
      };

      preConfigure =
        let
          gvdb = final.fetchFromGitLab {
            domain = "gitlab.gnome.org";
            owner = "GNOME";
            repo = "gvdb";
            rev = "2b42fc75f09dbe1cd1057580b5782b08f2dcb400";
            hash = "sha256-CIdEwRbtxWCwgTb5HYHrixXi+G+qeE1APRaUeka3NWk=";
          };
        in
        ''
          cp -a "${gvdb}" ./subprojects/gvdb
        '';
    });
  })
];
  # Enable the X11 windowing system and desktop environment
  services.xserver.enable = true;
  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
  };
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "de";

  services.gnome.gnome-keyring.enable = true;
  services.gnome.gnome-online-accounts.enable = true;

  # Exclude unnecessary GNOME packages, maintain essential ones
  environment.gnome.excludePackages = (
    with pkgs;
    [
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
}
