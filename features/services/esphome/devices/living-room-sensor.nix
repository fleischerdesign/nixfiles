# features/services/esphome/devices/living-room-sensor.nix
# Declarative ESPHome Device Specification for Living Room Climate & Multi-Sensor
{
  pkgs,
  ...
}:

let
  deviceConfigYaml = pkgs.writeText "living-room-sensor.yaml" ''
    esphome:
      name: hom-sns-01
      friendly_name: "Wohnzimmer Multi-Sensor"

    esp32:
      board: esp32dev
      framework:
        type: esp-idf

    wifi:
      ssid: "VYRX"
      manual_ip:
        static_ip: 10.10.30.25
        gateway: 10.10.10.10
        subnet: 255.255.255.0
        dns1: 10.10.10.10

    ota:
      platform: esphome

    logger:
      level: INFO

    time:
      - platform: sntp
        servers:
          - 10.10.10.10

    i2c:
      sda: 21
      scl: 22
      scan: true

    sensor:
      - platform: bme280_i2c
        temperature:
          name: "Wohnzimmer Temperatur"
        humidity:
          name: "Wohnzimmer Luftfeuchtigkeit"
        pressure:
          name: "Wohnzimmer Luftdruck"
        address: 0x76
        update_interval: 60s
  '';
in
{
  inherit deviceConfigYaml;
}
