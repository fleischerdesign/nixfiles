# features/services/esphome/templates/sonoff-basic.nix
# Reusable, declarative specification for Sonoff Basic (ESP8266 / esp01_1m) inline relays.
#
# The device owns no network identity of its own: it takes its address from DHCP, and the
# reservation for its MAC in `my.topology.devices` is the single source for what that address
# is. A hardcoded `manual_ip` here would duplicate that reservation.
#
# Every credential is referenced as an ESPHome `!secret`, never embedded. The names below are
# resolved from a `secrets.yaml` that the sync engine renders at flash time from SOPS, so no
# secret ever reaches the Nix store or the repository.
{ pkgs, lib, ... }:

{
  name,
  friendlyName,
  buttonPin ? 1,
  buttonTrigger ? "on_state",
  # [ { ssid = "..."; secret = "wifi_psk"; } ] - several networks, tried in order. Holding both
  # the current and the future SSID is what makes renaming the access point a non-event.
  wifiNetworks,
}:

let
  # Deliberately a plain (non-indented) string: a nested `''` block would strip its own
  # indentation, and interpolated text is inserted verbatim - so the columns below are the
  # columns in the generated file (items under `networks:`, credentials one level deeper).
  networkList = lib.concatMapStrings (
    n: "    - ssid: \"${n.ssid}\"\n      password: !secret ${n.secret}\n"
  ) wifiNetworks;

  configContent = ''
    esphome:
      name: ${name}
      friendly_name: "${friendlyName}"

    esp8266:
      board: esp01_1m

    logger:

    api:
      encryption:
        key: !secret api_key

    ota:
      - platform: esphome
        password: !secret ota_password

    wifi:
      networks:
    ${networkList}
      ap:
        ssid: "${name}-fallback"
        password: !secret fallback_ap_password

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
        name: "Relais"
        pin: GPIO12
        id: relay
        on_turn_off:
          if:
            condition:
              - switch.is_on: blue_led
            then:
              - switch.turn_off: blue_led

      - platform: gpio
        name: "Status-LED"
        id: blue_led
        pin:
          number: GPIO13
          inverted: True
        entity_category: diagnostic
  '';
in
{
  deviceConfigYaml = pkgs.writeText "${name}.yaml" configContent;
}
