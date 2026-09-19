# features/services/esphome/devices/switches.nix
# Per-device parameters of the Sonoff Basic relay fleet: name, human label, and the physical
# button wiring. Everything else is derived - the address comes from the MAC reservation in
# `my.topology.devices`, and every credential is rendered from SOPS at flash time
# (the template only emits `!secret` references, never values).
{
  hom-rly-01 = {
    name = "hom-rly-01";
    friendlyName = "Arbeitszimmer Relais";
    buttonPin = 1;
    buttonTrigger = "on_state";
  };

  hom-rly-02 = {
    name = "hom-rly-02";
    friendlyName = "Bad Relais";
    buttonPin = 1;
    buttonTrigger = "on_state";
  };

  hom-rly-03 = {
    name = "hom-rly-03";
    friendlyName = "Ender 3D-Drucker Relais";
    buttonPin = 0;
    buttonTrigger = "on_press";
  };

  hom-rly-06 = {
    name = "hom-rly-06";
    friendlyName = "Küche Relais";
    buttonPin = 1;
    buttonTrigger = "on_state";
  };

  hom-rly-07 = {
    name = "hom-rly-07";
    friendlyName = "Schlafzimmer Relais";
    buttonPin = 0;
    buttonTrigger = "on_press";
  };

  hom-rly-08 = {
    name = "hom-rly-08";
    friendlyName = "Sofa Relais";
    buttonPin = 1;
    buttonTrigger = "on_state";
  };
}
