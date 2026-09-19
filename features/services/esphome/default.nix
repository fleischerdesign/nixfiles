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
  topology = config.my.topology;
  specs = import ./devices/switches.nix;
  mkSonoff = import ./templates/sonoff-basic.nix { inherit pkgs lib; };

  # The device stores both the fleet WLAN and, while the migration is in progress, the old name
  # the access point still radiates. That is what lets the relays be flashed *before* the AP is
  # renamed without locking anything out (DEPLOYMENT.md 8.6).
  legacySsid = topology.hosts.hom-ap-01.migration.ssid or null;
  wifiNetworks = [
    {
      ssid = topology.wifi.ssid;
      secret = "wifi_psk";
    }
  ]
  ++ lib.optional (legacySsid != null) {
    ssid = legacySsid;
    secret = "wifi_psk_legacy";
  };

  # Only devices the topology can pin down: its MAC reservation is what gives the firmware a
  # stable address, and the address is what discovery needs.
  managed = lib.filterAttrs (name: device: device.mac != null && specs ? ${name}) topology.devices;

  # Where sops-nix materializes each device's credentials on this host.
  secretPath = name: "esphome/devices/${name}";
  deviceSecrets = lib.flatten (
    lib.mapAttrsToList (name: _: [
      "${secretPath name}/api_key"
      "${secretPath name}/ota_password"
      "${secretPath name}/ap_password"
    ]) managed
  );

  mkDevicePackage =
    name: device: spec:
    pkgs.writeShellScriptBin "esphome-sync-${name}" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.esphome
          pkgs.iproute2
          pkgs.iputils
        ]
      }:$PATH"
      exec ${pkgs.python3}/bin/python3 ${./sync.py} \
        --config "${(mkSonoff (spec // { inherit wifiNetworks; })).deviceConfigYaml}" \
        --name "${name}" \
        --device "${device.ipv4}" \
        --secret-dir "/run/secrets/${secretPath name}" \
        --wifi-psk-file "/run/secrets/services/wifi/psk" \
        --legacy-wifi-psk-file "/run/secrets/services/wifi/legacy_psk" \
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

    # Rendered from SOPS as individual files; the sync engine assembles the secrets.yaml ESPHome
    # resolves `!secret` against, so no credential is ever embedded in the generated firmware
    # configuration or written into the Nix store.
    sops.secrets = lib.genAttrs (
      deviceSecrets
      ++ [
        "services/wifi/psk"
        "services/wifi/legacy_psk"
      ]
    ) (_: { });

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
      name: device: mkDevicePackage name device specs.${name}
    ) managed;
  };
}
