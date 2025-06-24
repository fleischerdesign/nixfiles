{ config, lib, ... }:
{
  options.my.nixos.audio.pipewire.enable = lib.mkEnableOption "PipeWire audio";

  config = lib.mkIf config.my.nixos.audio.pipewire.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
