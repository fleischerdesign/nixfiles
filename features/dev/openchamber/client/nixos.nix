# The OpenChamber desktop client. It owns no agent state: the server keeps the projects and the
# sessions, and this host only stores a device-scoped token in OpenChamber's own settings file.
#
# Provisioning is automatic on every start, including the `app.relaunch()` path that bypasses a
# launcher wrapper (the desktop package carries a narrow hook in `entry.mjs`). The token is minted
# over a dedicated, forced-command SSH key whose literal device id is fixed in authorized_keys.
#
# Network access is the native desktop listener, not a second headless server: the embedded engine
# binds 0.0.0.0 so a peer can reach it, which upstream only does with a UI password set. The
# password is a per-host SOPS secret; the forced-command mint helper is the only other reader. The
# firewall rule below is derived from the endpoint contract and admits exactly the peer desktops on
# the WireGuard interface, never the LAN and never the internet.
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

  # One engine per execution host. The embedded desktop engine is the only server on a client host,
  # so a headless server beside it would own a second project store.
  serverHostNames = lib.attrNames (
    lib.filterAttrs (_: host: host.config.my.features.dev.openchamber.server.enable or false) systems
  );

  # The fleet's device public keys are declared once on the server feature and projected here, so a
  # desktop peer authorizes the same key the central server already trusts.
  deviceKeys = lib.foldl' (
    acc: name: acc // (systems.${name}.config.my.features.dev.openchamber.server.deviceKeys or { })
  ) { } serverHostNames;

  # Desktops that expose their native listener. The inventory decides the peer set: every other
  # host with network access enabled is a peer, and the local entry is upstream's own.
  peerHostNames = lib.attrNames (
    lib.filterAttrs (
      name: host:
      name != cfg.deviceId && host.config.my.features.dev.openchamber.client.networkAccess.enable
    ) systems
  );

  # A reachable remote instance is a host whose server already admits this device, or a peer desktop
  # whose native listener is declared. Placement is read from the evaluated inventory, so a host
  # that only runs the client, or a future server that has not admitted this device yet, is not
  # advertised as a broken entry. The local instance is never listed: upstream already has it.
  remoteHostNames = lib.attrNames (
    lib.filterAttrs (
      name: host:
      name != cfg.deviceId
      && (
        let
          system = host.config;
        in
        (
          system.my.features.dev.openchamber.server.enable
          && builtins.hasAttr cfg.deviceId (system.my.features.dev.openchamber.server.devices)
        )
        || system.my.features.dev.openchamber.client.networkAccess.enable
      )
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

  mint = pkgs.writeShellApplication {
    name = "openchamber-mint";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      export OPENCHAMBER_MINT_CONFIG="''${OPENCHAMBER_MINT_CONFIG:-/etc/openchamber/mint.json}"
      exec ${pkgs.nodejs_22}/bin/node ${../mint.mjs} "$@"
    '';
  };

  allowlistFile = "/etc/openchamber/bootstrap-devices";
  bootstrapUser = "openchamber-bootstrap";
  bootstrapGroup = "openchamber-bootstrap";

  mintConfig = pkgs.writeText "openchamber-mint.json" (
    builtins.toJSON {
      # The native listener binds 0.0.0.0 when network access is on; loopback is one of its addresses
      # and stays on this host, so a minted token never travels over a public interface.
      serverUrl = "http://127.0.0.1:${toString cfg.networkAccess.port}";
      passwordFile = config.sops.secrets.${cfg.networkAccess.bootstrapPasswordSecret}.path;
      allowlistFile = allowlistFile;
    }
  );

  peerAuthorizedKeys = map (
    host: ''restrict,command="${mint}/bin/openchamber-mint ${host}" ${deviceKeys.${host}}''
  ) peerHostNames;
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

    networkAccess = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Expose this desktop's embedded server over the mesh. Upstream binds 0.0.0.0 only when a
          desktop UI password is set; the firewall admits only the declared peer desktops on the
          WireGuard interface.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 7337;
        description = ''
          Stable port of the native listener. It is recorded in the desktop settings so the app
          tries it before falling back to a random port, and the peer registry uses the same value.
        '';
      };

      uiPasswordSopsFile = lib.mkOption {
        type = lib.types.path;
        default = ../../../../secrets/openchamber-desktop-${cfg.deviceId}.yaml;
        description = "SOPS document holding this desktop's UI password.";
      };

      uiPasswordSecret = lib.mkOption {
        type = lib.types.str;
        default = "services/openchamber/desktop-password/${cfg.deviceId}/user";
        description = "SOPS secret holding the UI password, readable by the primary user.";
      };

      bootstrapPasswordSecret = lib.mkOption {
        type = lib.types.str;
        default = "services/openchamber/desktop-password/${cfg.deviceId}/bootstrap";
        description = "The same password, readable by the forced-command bootstrap account.";
      };
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
        enables the headless server and its authoritative `devices` allowlist already contains this
        device, or when it exposes its native desktop listener as a peer. The mesh URL and bootstrap
        address come from the topology and the endpoint contract; no host name or address is written
        twice. The local instance is not in this list.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # One OpenCode engine per execution host. The desktop already starts its embedded server in
        # the user's session; a headless server beside it would own a second engine and a second
        # project store on the same machine.
        assertion = !(config.my.features.dev.openchamber.server.enable or false);
        message = "openchamber: a client host must not also enable the headless server";
      }
    ];

    sops.secrets = lib.mkMerge [
      {
        ${cfg.deviceKeySecret} = {
          sopsFile = cfg.deviceKeySopsFile;
          key = "ssh_key";
          owner = config.my.user.primary;
          mode = "0400";
        };
      }
      (lib.mkIf cfg.networkAccess.enable {
        ${cfg.networkAccess.uiPasswordSecret} = {
          sopsFile = cfg.networkAccess.uiPasswordSopsFile;
          key = "ui_password";
          owner = config.my.user.primary;
          mode = "0400";
        };
        ${cfg.networkAccess.bootstrapPasswordSecret} = {
          sopsFile = cfg.networkAccess.uiPasswordSopsFile;
          key = "ui_password";
          owner = "root";
          group = bootstrapGroup;
          mode = "0440";
        };
      })
    ];

    # The native desktop listener's password. Upstream reads it from the desktop settings file; the
    # provisioning adapter merges it into that file as the primary user (mode 0600). The bootstrap
    # reader is a second declaration of the same SOPS key, so the forced-command helper can sign in
    # locally without any client ever receiving the password.
    home-manager.sharedModules = [ ./home.nix ];

    # The native listener is a real listener, so it is declared like every other one: the firewall
    # derives its rule from this contract, scoped to the WireGuard interface and the peer desktops.
    my.contracts.provides.openchamber = lib.mkIf cfg.networkAccess.enable {
      endpoints.web = {
        port = cfg.networkAccess.port;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          fromHosts = peerHostNames;
        };
      };
    };

    users.groups.${bootstrapGroup} = lib.mkIf cfg.networkAccess.enable { };
    users.users.${bootstrapUser} = lib.mkIf cfg.networkAccess.enable {
      isSystemUser = true;
      group = bootstrapGroup;
      home = "/";
      createHome = false;
      shell = "${pkgs.bash}/bin/bash";
      description = "OpenChamber desktop device bootstrap";
      openssh.authorizedKeys.keys = peerAuthorizedKeys;
    };

    environment.etc."openchamber/bootstrap-devices" = lib.mkIf cfg.networkAccess.enable {
      text = lib.concatStringsSep "\n" peerHostNames + "\n";
    };
    environment.etc."openchamber/mint.json" = lib.mkIf cfg.networkAccess.enable {
      source = mintConfig;
    };
  };
}
