# features/media/spotify/nixos.nix - Spotify with Spicetify: the system side is the switch.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.media.spotify;
in
{
  options.my.features.media.spotify = {
    enable = lib.mkEnableOption "Spotify with Spicetify";
  };

  config = lib.mkIf cfg.enable {
    my.features.system.audio.enable = true;
    my.features.system.wayland.enable = true;

    # This feature is purely for Home Manager: the user half lives in home.nix, so the system side is
    # the switch and the per-user side is the implementation.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
