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
  nft = import ../../../../lib/nftables.nix { inherit lib; };
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
  # The mesh carries the overlay, plus the home zones that hold devices without an overlay identity.
  # Which zones those are is derived in the topology (`announcedZones`) and not listed here: a device
  # with one address and no second one is the only thing a node outside the LAN cannot reach any
  # other way, and a host zone is never carried, because its hosts answer at their overlay address.
  # The host that carries them is `my.topology.lanRouter` - the host that routes a zone is the only
  # one that may claim it, because cryptokey routing has exactly one owner per prefix.
  isLanRouter = ownHostname == topology.lanRouter;
  announcedCidrs = map (zone: topology.subnets.${zone}.cidr) topology.announcedZones;

  # --- the device policy ---------------------------------------------------------------------------
  # The carried zones exist so that a node outside the LAN can reach the devices in them. Reaching them
  # is not the same as being allowed to use them: this used to be one blanket rule - `ip saddr <mesh>
  # accept` - which made the routing decision and the permission decision the same decision, so every
  # mesh member reached every device on every port (measured: the printer answered on 80, 443 and 631,
  # the relays on 6053). A device now declares what it offers and who may use it
  # (`my.topology.devices.<name>.endpoints`), the trust lattice says which addresses carry which level
  # (`my.topology.sourcesByTrust`), and the LAN router forwards exactly that - inserted at the head of
  # the forward chain and guarded, the way the input lattice already is. Everything else stays closed:
  # a port nobody declared is a port nobody reaches, which is the only shape that remains true when the
  # next mesh-reachable device is added.
  #
  # Only IPv4 sources are used. A device has one address and it is an IPv4 one, so a v6 rule could only
  # ever match nothing - and a rule that matches nothing is the failure mode this whole projection
  # exists to make visible.
  # The rules are nftables matches, not commands. The firewall renders them into its own forward chain,
  # whose policy is `drop`, so a declaration is the only thing that opens a path and a declaration that
  # disappears takes its rule with it. The previous shape wrote `iptables` commands into `extraCommands`,
  # which cost twice: a syntax error stopped the firewall mid-reload (and with it the NAT of a whole
  # zone), and a rule whose declaration was withdrawn stayed in the chain forever.
  #
  # A device has one address and it is an IPv4 one, so the sources are filtered to that family: a v6
  # address in the set would make the rule match nothing while looking like it does something.
  devicePolicy = lib.concatLists (
    lib.mapAttrsToList (
      deviceName: device:
      lib.concatLists (
        lib.mapAttrsToList (
          endpointName: endpoint:
          let
            sources = lib.filter (address: !(lib.hasInfix ":" address)) (
              nft.sourcesOfTrust topology endpoint.from
            );
            protocols =
              if endpoint.protocol == "both" then
                [
                  "tcp"
                  "udp"
                ]
              else
                [ endpoint.protocol ];
          in
          map (
            proto:
            nft.rule [
              ''iifname "${cfg.interfaceName}"''
              "ip saddr ${nft.addressSet sources}"
              "ip daddr ${device.ipv4}"
              "${proto} dport ${toString endpoint.port}"
              "accept"
              ''comment "device-policy-${deviceName}-${endpointName}"''
            ]
          ) protocols
        ) device.endpoints
      )
    ) (lib.filterAttrs (_: device: builtins.elem device.zone topology.announcedZones) topology.devices)
  );

  # There is deliberately no deny rule for the carried zones. Under the nftables implementation the
  # forward chain's own policy is `drop` (`networking.firewall.filterForward`), so everything nobody
  # declared above is closed by construction. The previous implementation needed an explicit deny because
  # the iptables forward chain accepted by default - measured: without it the relays' 6053 and the
  # printer's web interface stayed reachable from the hub, and with the explicit deny the *withdrawal* of
  # a rule never happened at all.

  meshCidr = topology.subnets.mesh.cidr or "10.10.100.0/24";

  # A host with its own address in a home zone *is* in the home LAN: its zone gateway reaches every
  # other home zone directly, so a tunnel route for one would shadow a shorter path - measured: a
  # node that carried them while sitting inside the LAN sent its infra and iot traffic out through
  # the relays and back. A node without such an address roams, and needs the carried zones in its
  # tunnel: abroad it has no other path to them.
  insideLan =
    ownHost != null && ownHost.ipv4 != null && builtins.elem (ownHost.zone or "") topology.lanZones;

  meshLanRoutes = if insideLan then [ ] else announcedCidrs;

  # What a peer delivers: its own overlay address, plus the home zones the LAN router carries.
  deliveredBy =
    name: peer:
    [ "${peer.wireguardIpv4}/32" ]
    ++ lib.optional (peer.wireguardIpv6 != null) "${peer.wireguardIpv6}/128"
    ++ lib.optionals (name == topology.lanRouter) announcedCidrs;

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
        name: peer:
        {
          publicKey = peer.wireguardPublicKey;
          allowedIPs = deliveredBy name peer;
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
    # The mesh's own listening socket, declared like every other listener instead of being opened here: a
    # host that accepts incoming handshakes (a relay, or a host with a public address) has it open, a
    # spoke keeps it to itself - it dials out and is never dialled. One place decides exposure, and the
    # exposure inventory can see the socket.
    my.contracts.provides.wireguard = {
      endpoints.transport = {
        port = cfg.port;
        protocol = "udp";
        scope = "isolated";
        directAccess = {
          enable = true;
          interface = if isRelay || (ownHost != null && ownHost.ipv4 != null) then "all" else "local";
          protocol = "udp";
        };
      };
    };

    # 1. Firewall rules
    networking.firewall = {
      # The transport port is opened by the contract projection above, not here.
      # No trusted interface. Arriving over the mesh is a transport fact, not a permission: what a host
      # serves there it declares. The endpoints contract projects onto this interface the ports an ingress
      # proxies (a named endpoint) and the ones declared for the mesh explicitly, and the administrative
      # path is declared where SSH lives. Measured before: every mesh node reached every listening port of
      # every other node, including the databases and the monitoring exporters.
      checkReversePath = "loose";
      # No blanket rule for the carried zones. The host that routes the home LAN forwards what the
      # devices there declare and whoever the inventory says may ask (`devicePolicy`, projected into the
      # forward chain below): routing says where a packet may go, this says who may send it, and a rule
      # that answers both questions with "everyone" is not a policy.
    };

    assertions = [
      {
        assertion = topology.hosts ? ${topology.lanRouter};
        message = "WireGuard: my.topology.lanRouter names '${topology.lanRouter}', which is not a declared host, so the home zones would be carried by nobody.";
      }
      {
        # A carried zone is carried because a device in it has no overlay identity - and a device that
        # DHCP cannot serve is not reachable either, so the route would lead into a hole.
        assertion = builtins.all (
          zone:
          lib.any (device: device.zone == zone && device.ipv4 != null && device.mac != null) (
            lib.attrValues topology.devices
          )
        ) topology.announcedZones;
        message = "WireGuard: a home zone is carried into the mesh (${lib.concatStringsSep ", " topology.announcedZones}) that holds no inventarised device with an address and a MAC, so the route would lead into a hole.";
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

    # 4. MSS clamping, relay transit and the device policy - all of it declarative.
    #
    # Clamping modifies packets, so it belongs in a chain at the mangle priority rather than in the filter
    # chain, and it is scoped to the tunnel because that is where a smaller MTU has to survive an uplink
    # that never reports one. It lives in its own table instead of `networking.nftables.ruleset`: a
    # non-empty `ruleset` makes the nftables service flush everything before loading it, which would take
    # the firewall's own chains with it, while a table is deleted and recreated on every update.
    networking.nftables.tables.wireguard-mss = {
      family = "inet";
      content = ''
        chain clamp {
          type filter hook forward priority mangle; policy accept;
          iifname "${cfg.interfaceName}" tcp flags syn tcp option maxseg size set rt mtu
          oifname "${cfg.interfaceName}" tcp flags syn tcp option maxseg size set rt mtu
        }
      '';
    };

    # Transit between mesh peers, and what the carried zones' devices declare. Nothing else passes the
    # forward path: its policy is `drop` (`networking.firewall.filterForward`), so this list *is* the
    # forwarding policy instead of an allow-list in front of an accept.
    networking.firewall.extraForwardRules = lib.concatStringsSep "\n" (
      lib.optional isRelay ''iifname "${cfg.interfaceName}" oifname "${cfg.interfaceName}" accept''
      ++ lib.optionals (isLanRouter && topology.announcedZones != [ ]) devicePolicy
    );

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

          # What a rendered client routes through the mesh: the ingress - a node, whose public address a
          # client that resolves per network must be able to reach from inside the VPN - and every zone
          # the mesh carries. The carried zones are what makes a device in them reachable at all, and a
          # client that is not at home has no other path to them: the relay it peers with carries them,
          # so the client must route them there.
          ingressAddress = (topology.hosts.${topology.ingressHost} or { }).ipv4 or null;
          clientRoutes = lib.optional (ingressAddress != null) "${ingressAddress}/32" ++ announcedCidrs;

          # The resolvers a rendered client uses *inside* the tunnel, and they are the overlay addresses
          # of the hosts the inventory declares as resolvers - the same doors the fleet's own hosts are
          # given, so there is one list of resolvers and not two.
          #
          # Measured without this line: the client's VPN network carries no DNS server at all
          # (`DnsAddresses: [ ]`), so Android cannot even resolve the name it was told to use for private
          # DNS - the network ends up `PrivateDnsBroken`, without `INTERNET` and without validation, while
          # the underlying network is fine, and notifications stop being rebuilt on the network the phone
          # is actually using.
          #
          # It does not replace private DNS: that setting is global and covers every network, including
          # the ones the tunnel is not up on; this line is what lets it work on the VPN network at all.
          # IPv4 only - the mesh is IPv4-primary, and whether the resolvers' overlay v6 listeners answer
          # is not something this file can verify.
          clientDns = map (resolver: topology.hosts.${resolver}.wireguardIpv4) (
            lib.filter (resolver: topology.hosts.${resolver}.wireguardIpv4 != null) topology.resolverHosts
          );

          # Apps this client keeps outside the tunnel - a per-device declaration, because the key exists
          # only in the Android implementation of the client. It decides which *network* such an app is
          # bound to, not which routes it takes: the client's VPN network is a split tunnel without the
          # `INTERNET` capability, and that is a network an app like Google's push transport refuses to
          # use - measured as notifications that only arrived once the tunnel was switched off.
          excludedApplications = client.excludedApplications or [ ];
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
                        DNS = ${lib.concatStringsSep ", " clientDns}
                        MTU = 1280
            ${lib.optionalString (
              excludedApplications != [ ]
            ) "            ExcludedApplications = ${lib.concatStringsSep ", " excludedApplications}\n"}

                        ${peers}'';
        }
      )
    );

    environment.systemPackages = lib.optional (cfg.clientConfigs != [ ]) pkgs.qrencode;
  };
}
