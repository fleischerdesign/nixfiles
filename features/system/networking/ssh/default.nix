{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.system.networking.ssh;
  hosts = config.my.topology.hosts;
  ownHost = hosts.${config.networking.hostName} or null;
  listenAddresses = lib.mkIf (ownHost != null) (
    lib.optional (ownHost.ipv4 != null) {
      addr = ownHost.ipv4;
      port = 22;
    }
    ++ lib.optional (ownHost.wireguardIpv4 != null) {
      addr = ownHost.wireguardIpv4;
      port = 22;
    }
    ++ lib.optional (ownHost.wireguardIpv6 != null) {
      addr = ownHost.wireguardIpv6;
      port = 22;
    }
  );

  # Overlay units that assign the addresses sshd binds to. sshd binds each
  # ListenAddress exactly once at startup and never rebinds, so it must start
  # after these units and wait until every address exists on some interface.
  overlayUnits = map (name: "wireguard-${name}.service") (
    lib.attrNames config.networking.wireguard.interfaces
  );
in
{
  options.my.features.system.networking.ssh = {
    enable = lib.mkEnableOption "SSH server, bound to the LAN and the mesh overlay only";
    deployKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Operator key. It replaces the fleet deploy key whose private half was destroyed when the
        # openclaw tunnel rendered its secret over ~/.ssh/deploy-key. That key is not kept here: a
        # trust anchor nobody can use, but which still grants root if it ever resurfaces, is a
        # liability rather than a safety net. A fresh fleet key is generated in the rotation.
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+bSErYniJev/+/UxsilaoxHGYW8oVpd3pYMQuuGStw fleis@Yorke"
        # Fleet deploy key (generated 2026-09-20, lives at ~/.ssh/nixfiles-deploy-key). It separates
        # two things that were conflated: the credential that *addresses the fleet* and the node
        # tunnel secret rendered from /run/secrets, whose lifetime belongs to a feature. Until now
        # ~/.ssh/config pointed every host at the tunnel key, so a service secret was the fleet's
        # root credential - which is how the previous fleet key was destroyed.
        # Fingerprint: SHA256:EduFlyoHwWJx3avw46lQsLksum5R0scm6z27OeqBeO4
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGuk66em/pg6jVlG2U6dTLFeQCOWjEzlyGGEWGvSM0hI nixfiles-deploy@vyrx-2.0"
      ];
      description = "Authorized SSH public keys for root deploy-rs access.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.sshd = {
      after = [ "network-online.target" ] ++ overlayUnits;
      wants = [ "network-online.target" ] ++ overlayUnits;

      preStart = lib.mkIf (config.services.openssh.listenAddresses != [ ]) (
        ''
          echo "Waiting for SSH listen addresses to be assigned..."
          for i in $(seq 1 60); do
            missing=0
        ''
        + lib.concatMapStrings (a: ''
          ${pkgs.iproute2}/bin/ip -o addr show 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qF "${a.addr}/" || missing=1
        '') config.services.openssh.listenAddresses
        + ''
            if [ "$missing" -eq 0 ]; then
              echo "All SSH listen addresses are assigned."
              break
            fi
            sleep 1
          done
        ''
      );
    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
      inherit listenAddresses;
    };

    users.users.root.openssh.authorizedKeys.keys = cfg.deployKeys;

    warnings = lib.optionals (cfg.enable && ownHost == null) [
      "SSH feature: host '${config.networking.hostName}' not found in topology — SSH will bind to all interfaces."
    ];
  };
}
