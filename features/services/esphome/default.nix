# features/services/esphome/default.nix
# Declarative ESPHome Device Manager & Microcontroller GitOps Engine.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.esphome;
  devices = config.my.topology.devices or { };
  switches = import ./devices/switches.nix { inherit pkgs lib; };

  mkDevicePackage =
    name: device: yamlConfig:
    pkgs.writeShellScriptBin "esphome-sync-${name}" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.esphome
          pkgs.iputils
        ]
      }:$PATH"
      exec ${pkgs.python3}/bin/python3 ${./sync.py} \
        --config "${yamlConfig}" \
        --device "${device.ipv4}" \
        --name "${name}" \
        "$@"
    '';
in
{
  options.my.features.services.esphome = {
    enable = lib.mkEnableOption "ESPHome Device Manager";

    devicePackages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = "Compiled hermetic activation packages for ESPHome microcontrollers";
    };
  };

  config = lib.mkIf cfg.enable {
    services.esphome = {
      enable = true;
      port = 6052;
    };

    my.endpoints.esphome-mdns = {
      host = config.networking.hostName;
      port = 5353;
      directAccess = {
        enable = true;
        protocol = "udp";
        interface = "all";
      };
      monitoring.http.enable = false;
    };

    my.endpoints.esphome = {
      host = config.networking.hostName;
      port = 6052;
      displayName = "ESPHome";
      group = "Infrastructure";
    };

    my.features.services.esphome.devicePackages = lib.mapAttrs (
      rlyName: rlySpec: mkDevicePackage rlyName devices.${rlyName} rlySpec.deviceConfigYaml
    ) (lib.filterAttrs (rlyName: _: devices ? ${rlyName}) switches);
  };
}
