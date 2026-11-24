{ ... }:
{
  imports = [
    # ./disk-config.nix  # Inactive: Enable when bootstrapping/reinstalling with Disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/notebook.nix
  ];

  networking.hostName = "mob-nb-01";

  # D11: the primary user is assigned, not discovered - alphabetical order must never
  # decide who owns a home directory.
  my.user.primary = "philipp";

  # Features
  # The graphical session comes from the personal-computer role (`roles/pc.nix`): Niri and
  # Noctalia, the same as the desktop.

  my.features.dev.openchamber = {
    enable = true;
    defaultHost = "hom-srv-01";
    serverOnlyClients = true;
  };
  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;
  my.features.services.openclaw.node = {
    enable = true;
    camera.enable = true;
    # Local development previews, without granting the entire private network.
    browser.allowedHostnames = [ "127.0.0.1" ];
  };

  my.features.media.gaming.sunshine.enable = false;

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  system.stateVersion = "24.05";
}
