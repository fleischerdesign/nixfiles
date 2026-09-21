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

  # A spoke routes the node plane, not the home LAN. A home zone is reached by *being* in it -
  # directly - and everything else through the mesh. Carrying the prefixes instead would send
  # them the long way out through the hubs and back, so a roaming node sitting in the home LAN
  # would fetch a home service over the WAN (measured: it carried infra, corp and iot and went
  # through the relays while at home). The rendered client configurations are built from the same
  # function, so a phone and a notebook cannot diverge in where they send LAN traffic.
  meshLanRoutes = [ ];

  # What a peer delivers: its own overlay address, plus the zones it announces into the mesh.
  deliveredBy =
    peer:
    [ "${peer.wireguardIpv4}/32" ]
    ++ lib.optional (peer.wireguardIpv6 != null) "${peer.wireguardIpv6}/128"
    ++ lanCidrsOf peer;

  # The relay hubs a node that is not itself a relay peers with. `lanRoutes` is what that node routes
  # into the home LAN over the mesh: empty for a node that sits inside a delivered zone (a tunnel
  # route would shadow its connected route), and every delivered zone for a roaming node. The NixOS
  # spokes and the rendered non-NixOS client configurations are both built from this one function, so
  # the two cannot diverge.
  relayPeersFor =
    lanRoutes:
    lib.mapAttrsToList (name: relay: {
      publicKey = relay.wireguardPublicKey;
      endpoint = "${relay.ipv4}:${toString wireguardPort}";
      allowedIPs =
        if name == effectivePrimaryHub then
          # Primary hub carries the entire mesh overlay for transit / inter-node routing, and the
          # home LAN zones a node without a permanent LAN presence needs.
          [
            meshCidr
          ]
          ++ lib.optional (topology.subnets ? mesh-ipv6) (
            topology.subnets.mesh-ipv6.cidr or "fd10:1000:100::/64"
          )
          ++ lanRoutes
        else
          # Secondary relay hub is directly reachable via host-specific route (/32 and /128).
          [
            "${relay.wireguardIpv4}/32"
          ]
          ++ lib.optional (relay.wireguardIpv6 != null) "${relay.wireguardIpv6}/128";
      persistentKeepalive = 25;
    }) relayHosts;

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
      relayPeersFor meshLanRoutes;
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

    clientConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Names of roaming clients in `my.topology.hosts` whose WireGuard configuration this host
        renders. A device that cannot run `networking.wireguard.interfaces` (a phone, a tablet) still
        needs the same relays and routes; it gets them as a wg-quick file whose private key
        `sops.template` injects at activation, because Nix cannot read a SOPS value at build time.
        The client's public key lives in the topology, so one inventory entry feeds both the relay's
        peer list and this file.
      '';
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
    ]
    ++ lib.map (name: {
      assertion =
        topology.hosts ? ${name}
        && topology.hosts.${name}.wireguardPublicKey != null
        && topology.hosts.${name}.ipv4 == null;
      message = "WireGuard client config '${name}': it must be a declared node with a public key and no LAN address, because it is provisioned from this file, not configured on the device.";
    }) cfg.clientConfigs;

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

    # 4. MSS Clamping and relay packet forwarding via iptables / ip6tables (docs/architecture.md 5.1)
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

    # 5. Secrets: this host's own WireGuard key and the private key of every client it renders, both
    # under the same convention `infra/wireguard/<name>_private_key`.
    sops.secrets = lib.mkMerge [
      { ${cfg.privateKeySecretName} = lib.mkDefault { }; }
      (lib.genAttrs (map (name: "infra/wireguard/${name}_private_key") cfg.clientConfigs) (_: { }))
    ];

    # 6. Render each client's wg-quick configuration. The relay peers and routes come from the same
    # function the NixOS spokes use; only the private key is injected here (at activation, by
    # sops-nix), because it must not be read at build time. `qrencode` turns the file into the QR the
    # WireGuard app scans once.
    sops.templates = lib.genAttrs' cfg.clientConfigs (
      name:
      lib.nameValuePair "wg-${name}.conf" (
        let
          client = topology.hosts.${name};
          addresses = [
            "${client.wireguardIpv4}/32"
          ]
          ++ lib.optional (client.wireguardIpv6 != null) "${client.wireguardIpv6}/128";

          # What a rendered client routes through the mesh. The ingress is a node, and a
          # client that resolves per network - a phone's private DNS - must be able to reach
          # the resolver's public door *inside* the VPN: the name resolves to the ingress's
          # public address, and Android then requires that address to be routable there.
          # Our clients reach the ingress through the mesh, so its address is simply part of
          # what they route: one /32, not the internet.
          ingressAddress = (topology.hosts.${topology.ingressHost} or { }).ipv4 or null;
          clientRoutes = lib.optional (ingressAddress != null) "${ingressAddress}/32";
          peers = lib.concatMapStrings (peer: ''
            [Peer]
            PublicKey = ${peer.publicKey}
            Endpoint = ${peer.endpoint}
            AllowedIPs = ${lib.concatStringsSep ", " peer.allowedIPs}
            PersistentKeepalive = ${toString peer.persistentKeepalive}

          '') (relayPeersFor clientRoutes);
        in
        {
          content = ''
            [Interface]
            PrivateKey = ${config.sops.placeholder."infra/wireguard/${name}_private_key"}
            Address = ${lib.concatStringsSep ", " addresses}
            MTU = 1280

            ${peers}'';
        }
      )
    );

    environment.systemPackages = lib.optional (cfg.clientConfigs != [ ]) pkgs.qrencode;
  };
}
