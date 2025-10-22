{
  ...
}:

{
hardware.bluetooth = {
    enable = true;
    # Empfohlen für BlueZ-Audio-Verbindungen
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
