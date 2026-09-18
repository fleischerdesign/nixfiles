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

    my.contracts.provides.esphome = {
      endpoints = {
        web = {
          port = 6052;
          protocol = "tcp";
          scope = "internal";
          auth = "authentik";
          subdomain = "esphome";
          dashboard = {
            show = true;
            displayName = "ESPHome";
            category = "Infrastructure";
            icon = "chip";
          };
        };

        mdns = {
          port = 5353;
          protocol = "udp";
          scope = "internal";
          directAccess = {
            enable = true;
            protocol = "udp";
            interface = "all";
          };
          monitoring.http.enable = false;
        };
      };
      storage = {
        stateDirs = [ "/var/lib/esphome" ];
      };
    };

    my.features.services.esphome.devicePackages = lib.mapAttrs (
      rlyName: rlySpec: mkDevicePackage rlyName devices.${rlyName} rlySpec.deviceConfigYaml
    ) (lib.filterAttrs (rlyName: _: devices ? ${rlyName}) switches);
  };
}
