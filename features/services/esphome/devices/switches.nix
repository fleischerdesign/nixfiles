# features/services/esphome/devices/switches.nix
# Per-device parameters of the Sonoff Basic relay fleet: name, human label, the physical button
# wiring, and what the relay switches - a lamp circuit (a `light` in Home Assistant) or a power
# circuit (the printer, which stays a `switch`). Everything else is derived - the address comes
# from the MAC reservation in `my.topology.devices`, and every credential is rendered from SOPS at
# flash time (the template only emits `!secret` references, never values).
#
# `friendlyName` is the device label Home Assistant shows and names the load, not the module. The
# entity itself is named after the function (`Licht` for a lamp, `Strom` for the printer's power),
# because ESPHome drops an entity that has no name of its own. Neither carries a room: the room is
# the Home Assistant area, which the entity ID already starts with.
{
  hom-rly-01 = {
    name = "hom-rly-01";
    friendlyName = "Deckenlampe";
    buttonPin = 1;
    buttonTrigger = "on_state";
    relayKind = "light";
  };

  hom-rly-02 = {
    name = "hom-rly-02";
    friendlyName = "Wandlampe";
    buttonPin = 1;
    buttonTrigger = "on_state";
    relayKind = "light";
  };

  hom-rly-03 = {
    name = "hom-rly-03";
    friendlyName = "3D-Drucker";
    buttonPin = 0;
    buttonTrigger = "on_press";
    # The printer's mains power, not a lamp: switching it on or off is the point.
    relayKind = "switch";
  };

  hom-rly-04 = {
    name = "hom-rly-04";
    friendlyName = "Fernseher";
    buttonPin = 1;
    buttonTrigger = "on_state";
    relayKind = "light";
  };

  hom-rly-06 = {
    name = "hom-rly-06";
    friendlyName = "Deckenlampe";
    buttonPin = 1;
    buttonTrigger = "on_state";
    relayKind = "light";
  };

  hom-rly-07 = {
    name = "hom-rly-07";
    friendlyName = "Deckenlampe";
    buttonPin = 0;
    buttonTrigger = "on_press";
    relayKind = "light";
  };

  hom-rly-08 = {
    name = "hom-rly-08";
    friendlyName = "Sofa";
    buttonPin = 1;
    buttonTrigger = "on_state";
    relayKind = "light";
  };
}
