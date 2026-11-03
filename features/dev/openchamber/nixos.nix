# OpenChamber server: the OpenCode web UI, bound to the host's mesh address and reached directly over
# WireGuard.
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
#
# Exposure is the mesh and nothing else: there is no publication, no public name and no ingress
# hop. A desktop reaches `http://<server mesh address>:<port>` through WireGuard; a hand-paired
# phone does the same and must therefore be a mesh member.
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
      # The unit binds the mesh address, not loopback; the local helper must dial the address the
      # listener actually owns.
      serverUrl = "http://${cfg.bindAddress}:${toString cfg.port}";
      passwordFile = config.sops.secrets.${cfg.uiPasswordSecret}.path;
      allowlistFile = allowlistFile;
    }
  );

  revokeConfig = pkgs.writeText "openchamber-revoke.json" (
    builtins.toJSON {
      serverUrl = "http://${cfg.bindAddress}:${toString cfg.port}";
      passwordFile = config.sops.secrets.${cfg.uiPasswordSecret}.path;
      allowlistFile = allowlistFile;
    }
  );

  goAccountsSeed = pkgs.writeShellApplication {
    name = "openchamber-go-accounts";
    runtimeInputs = [ pkgs.nodejs_24 ];
    text = ''
      exec ${pkgs.nodejs_24}/bin/node ${./go-accounts.mjs} "$@"
    '';
  };

  goAccountsConfig = pkgs.writeText "openchamber-go-accounts.json" (
    builtins.toJSON {
      serverUrl = "http://${cfg.bindAddress}:${toString cfg.port}";
      integrationID = cfg.goAccountIntegration;
      switchProvider = cfg.goAccountSwitchProvider;
      stateFile = "/var/lib/openchamber-nixfiles/go-accounts.json";
      opencodeDatabase = "${cfg.stateDir}/.local/share/opencode/opencode.db";
      slots = map (account: {
        slot = account.slot;
        secretId = account.slot;
        secret = account.apiKeySecret;
      }) cfg.goAccounts;
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
      description = "Port for the OpenChamber server, reached over the mesh only.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4;
      defaultText = lib.literalExpression "config.my.topology.hosts.<host>.wireguardIpv4";
      description = ''
        Specific mesh address the server binds to. It is narrower than 0.0.0.0 and the firewall
        admits only the declared client hosts on the WireGuard interface.
      '';
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

    goAccounts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            slot = lib.mkOption {
              type = lib.types.strMatching "[a-z0-9][a-z0-9-]{0,30}";
              description = "Stable slot name; it appears in the owned credential id and label.";
            };
            apiKeySecret = lib.mkOption {
              type = lib.types.str;
              description = ''
                SOPS secret holding this OpenCode Go API key. The key is staged into the seed unit with
                `LoadCredential` and never enters the Nix store, the unit environment, argv or a log.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        OpenCode Go API keys seeded into OpenCode's own credential store, in failover order. Accounts
        with the managed id shape are created, rotated when the declared key changes and removed when
        the slot is dropped; every other credential, including a manual Console sign-in, is left
        untouched. Empty by default, so a host without Go accounts runs no seed unit.
      '';
    };

    goAccountIntegration = lib.mkOption {
      type = lib.types.str;
      default = "opencode-go";
      description = ''
        OpenCode integration that stores Go API keys. `opencode-go` is the dedicated Go integration;
        the shared `opencode` integration also accepts a key, but mixing both would split the account
        list the failover switches through.
      '';
    };

    goAccountSwitchProvider = lib.mkOption {
      type = lib.types.str;
      default = "opencode-go";
      description = ''
        Model provider id given to `accountSwitchProviders`. OpenCode reports a Go model as
        `opencode-go/<model>`, which is also the integration that owns the key, so the credential
        list the plugin reads is the one this module seeds.
      '';
    };

    goAccountCleanup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep the seed unit running when `goAccounts` is empty, so emptying the list removes the
        accounts this module created and retires its `accountSwitchProviders` entry. Without it an
        empty list starts no unit and leaves the previous accounts in OpenCode's store.
      '';
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

    meshClientHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional inventory hosts admitted to the listener over the mesh, for a device that pairs
        by hand (a phone) instead of through the bootstrap key. They receive no SSH grant.
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
      {
        # The id is interpolated into an authorized_keys `command=`; a shell metacharacter would
        # become part of the forced command line.
        assertion = lib.all (id: builtins.match "[a-z0-9][a-z0-9-]{1,62}" id != null) (
          lib.attrNames cfg.devices
        );
        message = "openchamber: a `server.devices.<id>` name must match [a-z0-9][a-z0-9-]{1,62}";
      }
      {
        assertion = lib.all (host: config.my.topology.hosts ? ${host}) cfg.meshClientHosts;
        message = "openchamber: every `server.meshClientHosts` entry must be an inventory host";
      }
      {
        assertion =
          (lib.unique (map (account: account.slot) cfg.goAccounts))
          == map (account: account.slot) cfg.goAccounts;
        message = "openchamber: every `server.goAccounts.<slot>` must be unique";
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
      # No writable home: the forced command needs neither HOME nor a working directory, and a
      # missing home makes sshd log a chdir warning on every mint.
      home = "/";
      createHome = false;
      shell = "${pkgs.bash}/bin/bash";
      description = "OpenChamber device bootstrap";
      openssh.authorizedKeys.keys = lib.mapAttrsToList (
        deviceId: device:
        ''restrict,command="${mint}/bin/openchamber-mint ${deviceId}" ${device.sshPublicKey}''
      ) cfg.devices;
    };

    sops.secrets = {
      ${cfg.uiPasswordSecret} = {
        sopsFile = cfg.uiPasswordSopsFile;
        key = "ui_password";
        owner = "root";
        group = bootstrapGroup;
        mode = "0440";
        restartUnits = [ "openchamber.service" ];
      };
    }
    # The seed is another reader of the same declared keys the Gateway already uses. Declaring the
    # secrets here only adds the restart trigger; owner and mode stay whatever the owning feature set.
    // lib.genAttrs (map (account: account.apiKeySecret) cfg.goAccounts) (_: {
      restartUnits = [ "openchamber-go-accounts.service" ];
    });

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

    # Native Go accounts: read the declared keys once per activation/boot, create only what is
    # missing, rotate only the owned slot whose key changed and keep the selected account unless
    # that account is the one being replaced. The program writes through the running server's API,
    # so OpenChamber's own settings lock and OpenCode's credential store stay the single writers.
    systemd.services.openchamber-go-accounts =
      lib.mkIf (cfg.goAccounts != [ ] || cfg.goAccountCleanup)
        {
          description = "Seed OpenCode Go accounts into OpenCode's credential store";
          after = [ "openchamber.service" ];
          wants = [ "openchamber.service" ];
          wantedBy = [ "multi-user.target" ];
          restartTriggers = [ goAccountsConfig ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${goAccountsSeed}/bin/openchamber-go-accounts";
            Environment = [ "OPENCHAMBER_GO_CONFIG=${goAccountsConfig}" ];
            StateDirectory = "openchamber-nixfiles";
            StateDirectoryMode = "0700";
            UMask = "0077";
            # Secrets arrive as files: systemd stages each declared SOPS file under /run/credentials and
            # the program reads it there. Nothing secret is in the unit, the environment or argv.
            LoadCredential = [
              "ui_password:${config.sops.secrets.${cfg.uiPasswordSecret}.path}"
            ]
            ++ map (
              account: "${account.slot}:${config.sops.secrets.${account.apiKeySecret}.path}"
            ) cfg.goAccounts;
            # The program reads OpenCode's SQLite metadata (id + active) to keep the selected account
            # across a rotation. It never writes there; the API is the write path.
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };

    my.contracts.provides.openchamber = {
      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
        # Direct over the mesh: the listener is bound to the WireGuard address and the firewall
        # admits exactly the devices that may use it, not every mesh member and not the internet.
        directAccess = {
          enable = true;
          interface = "wireguard";
          fromHosts = lib.attrNames cfg.devices ++ cfg.meshClientHosts;
        };
      };

      # No probe: the prometheus contract's `localUrl` is loopback, while this listener is bound to
      # the WireGuard address. A local blackbox probe would report the service down from a healthy
      # host. A mesh-target probe belongs in the monitoring contract, not here as a false alarm.

      storage.dataDirs = [ cfg.stateDir ];
    };
  };
}
