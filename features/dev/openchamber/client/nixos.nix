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

  # Every host that runs a server and already lists this device in its authoritative allowlist is a
  # reachable remote instance. Placement is read from the evaluated inventory, so a host that only
  # runs the client, or a future server that has not admitted this device yet, is not advertised as
  # a broken entry. The local instance is upstream's built-in one and never appears here.
  remoteHostNames = lib.attrNames (
    lib.filterAttrs (
      _: host:
      let
        serverCfg = host.config.my.features.dev.openchamber.server or { };
      in
      (serverCfg.enable or false) && builtins.hasAttr cfg.deviceId (serverCfg.devices or { })
    ) systems
  );

  remoteHost =
    host:
    let
      system = systems.${host}.config;
      endpoint = system.my.contracts.provides.openchamber.endpoints.web;
      address = config.my.topology.hosts.${host}.wireguardIpv4;
    in
    {
      id = host;
      label = host;
      url = "http://${address}:${toString endpoint.port}";
      sshAddress = address;
    };
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

    remoteHosts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.str; };
            label = lib.mkOption { type = lib.types.str; };
            url = lib.mkOption { type = lib.types.str; };
            sshAddress = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      readOnly = true;
      default = if cfg.enable then map remoteHost remoteHostNames else [ ];
      description = ''
        Remote server instances derived from the evaluated inventory: a host is listed when it
        enables the server and its authoritative `devices` allowlist already contains this device.
        The mesh URL and bootstrap address come from the topology and the endpoint contract; no host
        name or address is written twice. The local instance is not in this list.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A server host that has not admitted this device is simply absent from `remoteHosts`: configured
    # and reachable are separate facts, and local work does not depend on any remote server.
    assertions = [
      {
        # One OpenCode engine per execution host. The desktop already starts its embedded server in
        # the user's session; a headless server beside it would own a second engine and a second
        # project store on the same machine.
        assertion =
          !(systems.${config.networking.hostName}.config.my.features.dev.openchamber.server.enable or false);
        message = "openchamber: a client host must not also enable the headless server";
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
