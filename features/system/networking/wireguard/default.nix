# features/system/networking/wireguard/default.nix
# Stateless Kernel-WireGuard Mesh Network (RFC 1918 / 10.10.100.0/24 & RFC 4193 / fd10:1000:100::/64).
# High-Availability Dual-Hub Active Relay Architecture (cld-edge-01 + cld-ops-01).
# Eliminates single points of failure, establishes encrypted node-to-node transport,
# and enforces longest-prefix cryptokey routing with automated MSS clamping.
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

  isRelay = ownHost != null && (ownHost.wireguardRelay or false);
  wireguardPort = cfg.port;

  # All other declared hosts with a valid wireguard IP and public key
  allPeersWithKeys = lib.filterAttrs (
    name: h: name != ownHostname && h.wireguardIpv4 != null && h.wireguardPublicKey != null
  ) topology.hosts;

  # Publicly reachable relay hubs with static IP and public key
  relayHosts = lib.filterAttrs (
    name: h:
    name != ownHostname && (h.wireguardRelay or false) && h.ipv4 != null && h.wireguardPublicKey != null
  ) topology.hosts;

  # Active primary hub used for subnet-wide transit (falls back to first available relay if configured hub unavailable)
  effectivePrimaryHub =
    if relayHosts ? ${cfg.primaryHub} then
      cfg.primaryHub
    else if relayHosts != { } then
      lib.head (lib.attrNames relayHosts)
    else
      cfg.primaryHub;

  # --- LAN reachability over the mesh ----------------------------------------------------------
  # The overlay alone is not enough: a roaming client has to reach the home LAN, whose services do
  # not all have a public name. Which zones a host delivers is declared in the topology as zone names
  # (`lanGateway`), so no CIDR is written twice; the host that delivers them announces them, every
  # other host routes them to it through its peer entry, and a host that is itself inside a zone
  # installs nothing for it - a mesh route for a subnet it is attached to would shadow its connected
  # route. This is the job Tailscale's subnet router used to do.
  lanCidrsOf = host: map (zone: topology.subnets.${zone}.cidr) (host.lanGateway or [ ]);

  # Everything any host delivers into the mesh. A CIDR may be delivered once, and the assertion in
  # `config` holds that: cryptokey routing has exactly one owner per prefix.
  deliveredCidrs = lib.concatMap lanCidrsOf (lib.attrValues topology.hosts);
  deliveredZones = lib.concatMap (host: host.lanGateway or [ ]) (lib.attrValues topology.hosts);

  ownDeliveredCidrs = if ownHost == null then [ ] else lanCidrsOf ownHost;

  meshCidr = topology.subnets.mesh.cidr or "10.10.100.0/24";

  announcesLan = ownDeliveredCidrs != [ ];

  # Membership in a zone, decided on the /24 network part - every zone here is a /24, and the
  # assertion below holds that assumption rather than trusting it.
  network = address: lib.concatStringsSep "." (lib.take 3 (lib.splitString "." address));

  # What this host routes over the mesh: every delivered zone it is not already inside and does not
  # deliver itself. A route for a subnet this host is attached to would shadow its connected route,
  # and one it delivers itself is local to begin with.
  meshLanRoutes = lib.filter (
    cidr:
    !(builtins.any (own: network own == network cidr) ownDeliveredCidrs)
    && !(ownHost != null && ownHost.ipv4 != null && network ownHost.ipv4 == network cidr)
  ) deliveredCidrs;

  # What a peer delivers: its own overlay address, plus the zones it announces into the mesh.
  deliveredBy =
    peer:
    [ "${peer.wireguardIpv4}/32" ]
    ++ lib.optional (peer.wireguardIpv6 != null) "${peer.wireguardIpv6}/128"
    ++ lanCidrsOf peer;

  # Map peers to NixOS wireguard peer attrsets
  peersConfig =
    if isRelay then
      # A relay hub peers with all nodes that have declared public keys
      lib.mapAttrsToList (
        _name: peer:
        {
          publicKey = peer.wireguardPublicKey;
          allowedIPs = deliveredBy peer;
          persistentKeepalive = 25;
        }
        // lib.optionalAttrs ((peer.wireguardRelay or false) && peer.ipv4 != null) {
          endpoint = "${peer.ipv4}:${toString wireguardPort}";
        }
      ) allPeersWithKeys
    else
      # Spoke connects directly to all declared relay hubs (cld-edge-01, cld-ops-01)
      lib.mapAttrsToList (name: relay: {
        publicKey = relay.wireguardPublicKey;
        endpoint = "${relay.ipv4}:${toString wireguardPort}";
        allowedIPs =
          if name == effectivePrimaryHub then
            # Primary hub carries the entire mesh overlay subnet for transit / inter-spoke routing,
            # and - for a host without a permanent LAN presence - the home LAN zones too, because the
            # hub routes them on to the host that delivers them.
            [
              meshCidr
            ]
            ++ lib.optional (topology.subnets ? mesh-ipv6) (
              topology.subnets.mesh-ipv6.cidr or "fd10:1000:100::/64"
            )
            ++ meshLanRoutes
          else
            # Secondary relay hub is directly reachable via host-specific route (/32 and /128)
            [
              "${relay.wireguardIpv4}/32"
            ]
            ++ lib.optional (relay.wireguardIpv6 != null) "${relay.wireguardIpv6}/128";
        persistentKeepalive = 25;
      }) relayHosts;
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
      default = 51820;
      description = "UDP listen port for WireGuard";
    };

    primaryHub = lib.mkOption {
      type = lib.types.str;
      default = "cld-edge-01";
      description = "Primary WireGuard relay hub hostname for subnet-wide overlay transit";
    };

    privateKeySecretName = lib.mkOption {
      type = lib.types.str;
      default = "infra/wireguard/${config.networking.hostName}_private_key";
      description = "SOPS secret identifier containing the WireGuard private key";
    };
  };

  config = lib.mkIf (cfg.enable && ownHost != null && ownHost.wireguardIpv4 != null) {
    # 1. Firewall rules
    networking.firewall = {
      # Listen on the public UDP port if the host is a public relay or has a public IP
      allowedUDPPorts = lib.optional (isRelay || ownHost.ipv4 != null) cfg.port;
      trustedInterfaces = [ cfg.interfaceName ];
      checkReversePath = "loose";
      # The host that delivers the LAN has to be allowed to forward mesh traffic into it; without
      # this the packets reach the gateway and stop there, because reaching the gateway's own
      # addresses is input, not forward.
      extraForwardRules = lib.optionalString announcesLan "ip saddr ${meshCidr} accept\n";
    };

    assertions = [
      {
        assertion = builtins.length deliveredZones == builtins.length (lib.unique deliveredZones);
        message = "WireGuard: ${lib.concatStringsSep ", " deliveredZones} delivers a zone into the mesh more than once; cryptokey routing has exactly one owner per prefix, so the route would be ambiguous.";
      }
      {
        assertion = builtins.all (cidr: lib.hasSuffix "/24" cidr) deliveredCidrs;
        message = "WireGuard: a delivered zone is not a /24 (${lib.concatStringsSep ", " deliveredCidrs}), but membership in a zone is decided on its /24 network part.";
      }
    ];

    # 2. Kernel packet forwarding on relay nodes
    boot.kernel.sysctl = lib.mkIf isRelay {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    };

    # 3. Kernel WireGuard interface configuration (Dual-Stack IPv4 / RFC 4193 ULA IPv6)
    networking.wireguard.interfaces.${cfg.interfaceName} = {
      # The mesh is the last resort for a prefix that is also directly reachable. A roaming client
      # that happens to be at home has a connected route to its own zone (NetworkManager gives wifi
      # 600), and a tunnel route at the default metric 0 would win over it and send LAN traffic out
      # through the hubs and back. The overlay itself has no competing route, so this only orders the
      # LAN prefixes the mesh carries.
      metric = 1000;
      ips = [
        "${ownHost.wireguardIpv4}/24"
      ]
      ++ lib.optional (ownHost.wireguardIpv6 != null) "${ownHost.wireguardIpv6}/64";
      listenPort = cfg.port;
      privateKeyFile = config.sops.secrets.${cfg.privateKeySecretName}.path;
      peers = peersConfig;
    };

    # 4. MSS Clamping and relay packet forwarding via iptables / ip6tables (ARCHITECTURE.md 5.1)
    networking.firewall.extraCommands = ''
      # TCP-MSS-Clamping for WireGuard interface (IPv4 & IPv6)
      ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o ${cfg.interfaceName} -j TCPMSS --clamp-mss-to-pmtu || true
      ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -i ${cfg.interfaceName} -j TCPMSS --clamp-mss-to-pmtu || true
      ${pkgs.iptables}/bin/ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -o ${cfg.interfaceName} -j TCPMSS --clamp-mss-to-pmtu || true
      ${pkgs.iptables}/bin/ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -i ${cfg.interfaceName} -j TCPMSS --clamp-mss-to-pmtu || true
    ''
    + lib.optionalString isRelay ''
      # Relay interface forwarding for inter-peer mesh transit
      ${pkgs.iptables}/bin/iptables -A FORWARD -i ${cfg.interfaceName} -o ${cfg.interfaceName} -j ACCEPT || true
      ${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${cfg.interfaceName} -o ${cfg.interfaceName} -j ACCEPT || true
    '';

    # 5. Assert that SOPS secret is declared
    sops.secrets.${cfg.privateKeySecretName} = lib.mkDefault { };
  };
}
