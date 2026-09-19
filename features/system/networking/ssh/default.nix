{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.system.networking.ssh;
  hosts = config.my.features.system.networking.topology.hosts;
  ownHost = hosts.${config.networking.hostName} or null;
  listenAddresses = lib.mkIf (ownHost != null) (
    lib.optional (ownHost.localIp != null) {
      addr = ownHost.localIp;
      port = 22;
    }
    ++ lib.optional (ownHost.tailscaleIp != null) {
      addr = ownHost.tailscaleIp;
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
  overlayUnits =
    lib.optional config.services.tailscale.enable "tailscaled.service"
    ++ map (name: "wireguard-${name}.service") (lib.attrNames config.networking.wireguard.interfaces);
in
{
  options.my.features.system.networking.ssh = {
    enable = lib.mkEnableOption "SSH server, bound to LAN and Tailscale only";
    deployKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUtA5kA9lDxzQjtgfMDKC+RLOaqSuUWF1gSaO8tjGCR deploy-rs"
      ];
      description = "Authorized SSH public keys for root deploy-rs access.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.system.networking.topology.enable = lib.mkDefault true;

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
