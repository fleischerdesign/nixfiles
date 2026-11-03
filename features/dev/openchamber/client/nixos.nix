# The OpenChamber desktop client. It owns no agent state: the server keeps the projects and the
# sessions, and this host only stores a device-scoped token in OpenChamber's own settings file.
#
# Provisioning is automatic on every start, including the `app.relaunch()` path that bypasses a
# launcher wrapper (the desktop package carries a narrow hook in `entry.mjs`). The token is minted
# over a dedicated, forced-command SSH key whose literal device id is fixed in authorized_keys.
{
  config,
  lib,
  pkgs,
  fleetConfigs,
  ...
}:

let
  cfg = config.my.features.dev.openchamber.client;
  systems = fleetConfigs.systems config;

  serverHost = fleetConfigs.uniqueHost {
    inherit systems;
    matches = host: host.my.features.dev.openchamber.server.enable or false;
    role = "OpenChamber server";
  };

  server = systems.${serverHost}.config;
in
{
  options.my.features.dev.openchamber.client = {
    enable = lib.mkEnableOption "the OpenChamber desktop client with automatic provisioning";

    deviceId = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Device id; must be present in the server's authoritative allowlist.";
    };

    desktopPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openchamber-desktop;
      defaultText = lib.literalExpression "pkgs.openchamber-desktop";
      description = "Patched OpenChamber desktop package (the provisioning hook is part of the overlay).";
    };

    deviceKeySopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../../../secrets/openchamber-device-${cfg.deviceId}.yaml;
      description = "SOPS document with this device's private bootstrap key, scoped to this host.";
    };

    deviceKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "services/openchamber/devices/${cfg.deviceId}/ssh_key";
      description = "SOPS secret holding this device's private bootstrap key.";
    };

    deviceKeyPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = config.sops.secrets.${cfg.deviceKeySecret}.path;
      description = "Rendered path of the private bootstrap key.";
    };

    serverHost = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = serverHost;
      description = "Inventory host that runs the OpenChamber server.";
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        if cfg.enable then
          "http://${
            config.my.topology.hosts.${serverHost}.wireguardIpv4
          }:${toString server.my.contracts.provides.openchamber.endpoints.web.port}"
        else
          "";
      description = ''
        Mesh URL derived from the server host's WireGuard address and the endpoint's declared port.
        The transport is WireGuard; there is no public name, so no DNS or ingress is involved.
      '';
    };

    serverSshAddress = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = if cfg.enable then config.my.topology.hosts.${serverHost}.wireguardIpv4 else "";
      description = "Mesh address the forced-command SSH bootstrap is pinned to.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.deviceId server.my.features.dev.openchamber.server.devices;
        message = "openchamber: device '${cfg.deviceId}' is not in ${serverHost}'s server.devices allowlist";
      }
      {
        assertion = server.my.features.dev.openchamber.server.enable;
        message = "openchamber: the client is enabled but the derived server host does not enable the server";
      }
    ];

    sops.secrets.${cfg.deviceKeySecret} = {
      sopsFile = cfg.deviceKeySopsFile;
      key = "ssh_key";
      owner = config.my.user.primary;
      mode = "0400";
    };

    home-manager.sharedModules = [ ./home.nix ];
  };
}
