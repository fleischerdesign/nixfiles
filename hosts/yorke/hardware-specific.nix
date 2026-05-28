_: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Empfohlen für BlueZ-Audio-Verbindungen
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
