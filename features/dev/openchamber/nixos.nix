# OpenChamber server: the OpenCode web UI, bound to the host's mesh address and reached through the
# ingress.
#
# The server owns all project data under one account (`openchamber`), never the Gateway's. The UI
# password is read from a SOPS secret through systemd's credential mechanism; a per-device SSH
# forced-command helper mints client tokens without ever putting the password on the client or in
# argv.
#
# The device list below is authoritative. Removing a device removes its SSH grant in the same
# activation; the revoke unit then invalidates its client token. A device that is only deleted from
# the settings UI would come back on its next mint, which is why the grant and the token are
# reconciled together here.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.dev.openchamber.server;
  bootstrapUser = "openchamber-bootstrap";
  bootstrapGroup = "openchamber-bootstrap";

  allowlistFile = "/etc/openchamber/bootstrap-devices";

  mint = pkgs.writeShellApplication {
    name = "openchamber-mint";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      export OPENCHAMBER_MINT_CONFIG="''${OPENCHAMBER_MINT_CONFIG:-/etc/openchamber/mint.json}"
      exec ${pkgs.nodejs_22}/bin/node ${./mint.mjs} "$@"
    '';
  };

  revoke = pkgs.writeShellApplication {
    name = "openchamber-revoke";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      export OPENCHAMBER_REVOKE_CONFIG="''${OPENCHAMBER_REVOKE_CONFIG:-/etc/openchamber/revoke.json}"
      exec ${pkgs.nodejs_22}/bin/node ${./revoke.mjs}
    '';
  };

  mintConfig = pkgs.writeText "openchamber-mint.json" (
    builtins.toJSON {
      serverUrl = "http://127.0.0.1:${toString cfg.port}";
      passwordFile = config.sops.secrets.${cfg.uiPasswordSecret}.path;
      allowlistFile = allowlistFile;
    }
  );

  revokeConfig = pkgs.writeText "openchamber-revoke.json" (
    builtins.toJSON {
      serverUrl = "http://127.0.0.1:${toString cfg.port}";
      passwordFile = config.sops.secrets.${cfg.uiPasswordSecret}.path;
      allowlistFile = allowlistFile;
    }
  );
in
{
  imports = [ inputs.openchamber.nixosModules.default ];

  options.my.features.dev.openchamber.server = {
    enable = lib.mkEnableOption "the OpenChamber server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7337;
      description = "Port for the OpenChamber server; the ingress proxies the public name to it.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4;
      defaultText = lib.literalExpression "config.my.topology.hosts.<host>.wireguardIpv4";
      description = ''
        Specific mesh address the server binds to. A public publication needs the ingress to reach
        the endpoint over the mesh (Naming I10); binding the mesh address is narrower than 0.0.0.0
        and the firewall admits only the ingress.
      '';
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "openchamber";
      description = "Public subdomain under the site's apex domain.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openchamber";
      description = "OpenChamber state and project data, owned by the service account.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "openchamber";
      description = "Account the server runs as. It must own `stateDir` and nothing of the Gateway.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "openchamber";
      description = "Group of the service account.";
    };

    uiPasswordSecret = lib.mkOption {
      type = lib.types.str;
      default = "services/openchamber/ui_password";
      description = "SOPS secret holding the server's UI password.";
    };

    uiPasswordSopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../../secrets/openchamber-server.yaml;
      description = "SOPS document holding the server's UI password, scoped to this host and the operator.";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.sshPublicKey = lib.mkOption {
            type = lib.types.str;
            description = "Public half of the device's dedicated SSH bootstrap key.";
          };
        }
      );
      default = { };
      description = ''
        Authoritative device allowlist. The attribute name is the device id and must equal the
        client host name. Removing an entry removes the SSH grant and revokes the client token.
      '';
    };

    mintPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Forced-command helper installed for every allowlisted device.";
    };

    revokePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Allowlist-to-token reconciliation helper.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.dev.openchamber.server.mintPackage = mint;
    my.features.dev.openchamber.server.revokePackage = revoke;

    assertions = [
      {
        assertion = cfg.devices != { };
        message = "openchamber: `server.devices` is empty; a server without a device cannot provision one";
      }
      {
        assertion = lib.all (key: lib.hasPrefix "ssh-" key) (
          map (device: device.sshPublicKey) (lib.attrValues cfg.devices)
        );
        message = "openchamber: every `server.devices.<id>.sshPublicKey` must be an OpenSSH public key";
      }
    ];

    users.groups.${cfg.group} = { };
    users.groups.${bootstrapGroup} = { };

    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.stateDir;
      createHome = true;
      description = "OpenChamber server";
    };

    # The forced command runs through this account's shell. It has no home and no writable path;
    # the only thing it can do is call the mint helper with the device id fixed in authorized_keys.
    users.users.${bootstrapUser} = {
      isSystemUser = true;
      group = bootstrapGroup;
      home = "/var/lib/openchamber-bootstrap";
      createHome = false;
      shell = "${pkgs.bash}/bin/bash";
      description = "OpenChamber device bootstrap";
      openssh.authorizedKeys.keys = lib.mapAttrsToList (
        deviceId: device:
        ''restrict,command="${mint}/bin/openchamber-mint ${deviceId}" ${device.sshPublicKey}''
      ) cfg.devices;
    };

    sops.secrets.${cfg.uiPasswordSecret} = {
      sopsFile = cfg.uiPasswordSopsFile;
      key = "ui_password";
      owner = "root";
      group = bootstrapGroup;
      mode = "0440";
      restartUnits = [ "openchamber.service" ];
    };

    # Upstream's own module owns the unit, credential loading and the process. The package and its
    # bundled OpenCode 2.2.5 stay exactly the pinned upstream artifacts; no second CLI is installed.
    services.openchamber = {
      enable = true;
      inherit (cfg) port user;
      host = cfg.bindAddress;
      uiPasswordFile = config.sops.secrets.${cfg.uiPasswordSecret}.path;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.openchamber.serviceConfig = {
      # The account is dedicated: it does not read any home directory, and its own state is the one
      # writable tree it needs.
      ProtectHome = true;
      InaccessiblePaths = [ "-/var/lib/openclaw" ];
      ReadWritePaths = [ cfg.stateDir ];
      UMask = "0077";
    };

    environment.etc."openchamber/bootstrap-devices".text =
      lib.concatStringsSep "\n" (lib.attrNames cfg.devices) + "\n";
    environment.etc."openchamber/mint.json".source = mintConfig;
    environment.etc."openchamber/revoke.json".source = revokeConfig;

    systemd.services.openchamber-revoke = {
      description = "Revoke OpenChamber tokens for devices no longer in the Nix allowlist";
      after = [ "openchamber.service" ];
      wants = [ "openchamber.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ allowlistFile ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${revoke}/bin/openchamber-revoke";
      };
    };

    systemd.timers.openchamber-revoke = {
      description = "Reconcile OpenChamber device tokens";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
      };
    };

    my.contracts.provides.openchamber = {
      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
        # The ingress proxies to the mesh address. The firewall admits only the ingress host, not
        # every mesh member, and the listener is bound to the mesh address rather than 0.0.0.0.
        directAccess = {
          enable = true;
          interface = "wireguard";
          fromHosts = [ config.my.topology.ingressHost ];
        };
      };

      publications.web = {
        scope = "public";
        endpoint = "web";
        subdomain = cfg.subdomain;
        auth = "none";
        publicExempt = "OpenChamber enforces its own UI password; the ingress only terminates TLS.";
      };

      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";

      storage.dataDirs = [ cfg.stateDir ];
    };
  };
}
