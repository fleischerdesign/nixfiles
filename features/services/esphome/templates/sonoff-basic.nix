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
  # What the relay switches: a lamp circuit is a `light` in Home Assistant, a power circuit (the
  # 3D printer) stays the `switch` it is. The domain also picks the action the button calls.
  relayKind,
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

  # The button calls the relay, and ESPHome names an action after the entity's domain - so the
  # declaration and the automation below move together.
  relayDomain = if relayKind == "light" then "light" else "switch";

  # A name is not optional: ESPHome marks an entity that carries only an `id`
  # (`config_validation.py`, `_entity_base_validator`) as internal, so it never reaches Home
  # Assistant. The entity therefore names the function, and the device label names the load.
  relayLabel = if relayKind == "light" then "Licht" else "Strom";

  # A rendered block lands under a key at a column of its own, but a nested `''` string strips its
  # indentation before it is interpolated (the same reason `networkList` above is a plain string).
  # The fragments below are therefore written flush and shifted to their parent key's column here.
  indentLines =
    n: text:
    lib.concatMapStrings (
      line: if line == "" then "\n" else "${lib.fixedWidthString n " " ""}${line}\n"
    ) (lib.splitString "\n" (lib.removeSuffix "\n" text));

  # A lamp circuit: Home Assistant registers `light.*`, and the relay is the light's output.
  lightEntity = ''
    output:
      - platform: gpio
        pin: GPIO12
        id: relay_output

    light:
      - platform: binary
        name: "${relayLabel}"
        id: relay
        output: relay_output
        on_turn_off:
          if:
            condition:
              - switch.is_on: blue_led
            then:
              - switch.turn_off: blue_led
  '';

  # A power circuit: the same GPIO, left as the switch it is.
  switchEntity = ''
    - platform: gpio
      name: "${relayLabel}"
      pin: GPIO12
      id: relay
      on_turn_off:
        if:
          condition:
            - switch.is_on: blue_led
          then:
            - switch.turn_off: blue_led
  '';

  ledEntity = ''
    - platform: gpio
      name: "Status-LED"
      id: blue_led
      pin:
        number: GPIO13
        inverted: True
      entity_category: diagnostic
  '';

  # The status LED stays a switch either way, so the light variant keeps a `switch:` block of its
  # own - an entity list lives under exactly one key.
  # The closing newline belongs to the template around it, not to this block.
  relayAndLed = lib.removeSuffix "\n" (
    if relayKind == "light" then
      "${lightEntity}\nswitch:\n${indentLines 2 ledEntity}"
    else
      "switch:\n${indentLines 2 switchEntity}\n${indentLines 2 ledEntity}"
  );

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
              - ${relayDomain}.is_off: relay
            then:
              - switch.turn_on: blue_led
              - ${relayDomain}.turn_on: relay
            else:
              - ${relayDomain}.turn_off: relay

    ${relayAndLed}
  '';
in
{
  deviceConfigYaml = pkgs.writeText "${name}.yaml" configContent;
}
