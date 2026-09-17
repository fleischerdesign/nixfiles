# features/system/networking/wireguard/default.nix
# Stateless Kernel-WireGuard Mesh Network (RFC 1918 / 10.10.100.0/24).
# Eliminates external control planes and establishes encrypted node-to-node transport.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.wireguard;
  topology = config.my.topology;
  ownHostname = config.networking.hostName;
  ownHost = topology.hosts.${ownHostname} or null;

  isHub = ownHostname == "cld-edge-01";
  wireguardPort = 51820;

  # Determine peers to connect to based on network topology
  # Hub connects to all hosts with a wireguard IP
  # Other nodes connect to the hub (and local subnet peers if direct)
  allPeersWithKeys = lib.filterAttrs (
    name: h: name != ownHostname && h.wireguardIpv4 != null && h.wireguardPublicKey != null
  ) topology.hosts;

  hubHost = topology.hosts.cld-edge-01 or null;

  # Map peers to NixOS wireguard peer attrsets
  peersConfig =
    if isHub then
      # Hub peers with everyone that has a public key
      lib.mapAttrsToList (_name: peer: {
        publicKey = peer.wireguardPublicKey;
        allowedIPs = [ "${peer.wireguardIpv4}/32" ];
        # Persistent keepalive for NAT traversal if peer is behind NAT
        persistentKeepalive = 25;
      }) allPeersWithKeys
    else
      # Spoke connects to hub
      lib.optional (hubHost != null && hubHost.wireguardPublicKey != null && hubHost.ipv4 != null) {
        publicKey = hubHost.wireguardPublicKey;
        allowedIPs = [
          "10.10.100.0/24" # Full mesh overlay routed through hub
        ];
        endpoint = "${hubHost.ipv4}:${toString wireguardPort}";
        persistentKeepalive = 25;
      };
in
{
  options.my.features.system.networking.wireguard = {
    enable = lib.mkEnableOption "Stateless Kernel-WireGuard Mesh Network";

    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "wg0";
      description = "Network interface name for the WireGuard tunnel";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = wireguardPort;
      description = "UDP listen port for WireGuard";
    };

    privateKeySecretName = lib.mkOption {
      type = lib.types.str;
      default = "wireguard_private_key";
      description = "SOPS secret identifier containing the WireGuard private key";
    };
  };

  config = lib.mkIf (cfg.enable && ownHost != null && ownHost.wireguardIpv4 != null) {
    # 1. Firewall rules
    networking.firewall = {
      # Only listen on the public UDP port if the host is reachable or is a hub
      allowedUDPPorts = lib.optional (ownHost.ipv4 != null) cfg.port;
      trustedInterfaces = [ cfg.interfaceName ];
      checkReversePath = "loose";
    };

    # 2. Kernel WireGuard interface configuration
    networking.wireguard.interfaces.${cfg.interfaceName} = {
      ips = [ "${ownHost.wireguardIpv4}/24" ];
      listenPort = cfg.port;
      privateKeyFile = config.sops.secrets.${cfg.privateKeySecretName}.path;
      peers = peersConfig;
    };

    # 3. MSS Clamping via nftables / iptables to prevent packet drop on MTU mismatches (ARCHITECTURE.md 5.1)
    networking.firewall.extraCommands = ''
      # TCP-MSS-Clamping for WireGuard interface
      ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o ${cfg.interfaceName} -j TCPMSS --clamp-mss-to-pmtu || true
      ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -i ${cfg.interfaceName} -j TCPMSS --clamp-mss-to-pmtu || true
    '';

    # 4. Assert that SOPS secret is declared
    sops.secrets.${cfg.privateKeySecretName} = lib.mkDefault { };
  };
}
