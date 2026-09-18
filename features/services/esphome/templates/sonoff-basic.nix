# features/services/esphome/templates/sonoff-basic.nix
# Reusable, declarative Nix specification for Sonoff Basic (ESP8266 / esp01_1m) switches.
# Implements complete hardware abstraction, captive portal fallback, and Home Assistant native API.
{ pkgs, lib, ... }:

{
  name,
  friendlyName,
  ipv4,
  buttonPin ? 1,
  buttonTrigger ? "on_state",
  apiEncryptionKey ? null,
  otaPassword ? null,
  apSsid ? null,
  apPassword ? null,
  wifiSsid ? "VYRX",
  wifiPassword ? null,
  gateway ? "10.10.10.10",
  subnet ? "255.255.255.0",
  dns1 ? "10.10.10.10",
}:

let
  actualApSsid = if apSsid != null then apSsid else name;
  actualApPassword = if apPassword != null then apPassword else "vyrx-setup-fallback";

  configContent = ''
    esphome:
      name: ${name}
      friendly_name: "${friendlyName}"

    esp8266:
      board: esp01_1m

    logger:

    ${lib.optionalString (apiEncryptionKey != null) ''
      api:
        encryption:
          key: "${apiEncryptionKey}"
    ''}
    ${lib.optionalString (apiEncryptionKey == null) ''
      api:
    ''}

    ota:
      - platform: esphome
        ${lib.optionalString (otaPassword != null) ''password: "${otaPassword}"''}

    wifi:
      ssid: "${wifiSsid}"
      ${lib.optionalString (wifiPassword != null) ''password: "${wifiPassword}"''}
      manual_ip:
        static_ip: ${ipv4}
        gateway: ${gateway}
        subnet: ${subnet}
        dns1: ${dns1}

      ap:
        ssid: "${actualApSsid}"
        password: "${actualApPassword}"

    captive_portal:

    binary_sensor:
      - platform: gpio
        id: push_button
        pin:
          number: GPIO${toString buttonPin}
          mode: INPUT_PULLUP
          inverted: True
        internal: true
        ${buttonTrigger}:
          if:
            condition:
              - switch.is_off: relay
            then:
              - switch.turn_on: blue_led
              - switch.turn_on: relay
            else:
              - switch.turn_off: relay

    switch:
      - platform: gpio
        name: "${friendlyName} Relais"
        pin: GPIO12
        id: relay
        on_turn_off:
          if:
            condition:
              - switch.is_on: blue_led
            then:
              - switch.turn_off: blue_led

      - platform: gpio
        id: blue_led
        pin:
          number: GPIO13
          inverted: True
  '';
in
{
  deviceConfigYaml = pkgs.writeText "${name}.yaml" configContent;
}
