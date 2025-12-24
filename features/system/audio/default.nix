# features/system/audio.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.audio;
in
{
  options.my.features.system.audio = {
    enable = lib.mkEnableOption "Audio configuration (Pipewire and related tools)";
  };

  config = lib.mkIf cfg.enable {
    services.pulseaudio.enable = false; # Disable PulseAudio to use Pipewire
    security.rtkit.enable = true; # Realtime scheduling for audio
    services.pipewire = {
      enable = true;
      alsa.enable = true; # ALSA support
      alsa.support32Bit = true; # 32-bit ALSA applications
      pulse.enable = true; # PulseAudio compatibility
      # jack.enable = true;             # JACK compatibility, if needed
    };

    services.pipewire.extraConfig.pipewire."99-min-quantum" = {
      "context.properties" = {
        "default.clock.min-quantum" = 1024;
      };
    };

    environment.systemPackages = with pkgs; [
      easyeffects # Audio effects processor
    ];
  };
}
