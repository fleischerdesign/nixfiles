# features/system/networking/gateway/default.nix
# Single-NIC Router-on-a-Stick Gateway & Network Services (RFC 1812).
# Declares central DHCP (Kea), NTP (Chrony), and Layer-3 IPv4 Forwarding/NAT
# completely driven by `config.my.topology`.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.system.networking.gateway;
  topology = config.my.topology;

  # Zones this host serves DHCP for, derived from the topology: the zone that holds the uplink (its
  # router is the uplink itself) plus the zones this host routes. Trust levels do not belong here -
  # they govern forwarding and NAT, not addressing, and the isolated iot zone still gets its
  # reservations. Adding a zone therefore needs no change in this file.
  uplinkZone = lib.findFirst (
    zone: (topology.subnets.${zone}.gateway or null) == cfg.uplinkGateway
  ) null (lib.attrNames topology.subnets);

  dhcpZones = lib.unique (lib.optional (uplinkZone != null) uplinkZone ++ cfg.routedZones);

  dhcpSubnets = map (zone: {
    inherit zone;
    config = topology.subnets.${zone};
  }) servedZones;

  # Determine static reservations for DHCP from hosts and devices declared in topology with MAC address
  hostsWithMac = lib.filterAttrs (_name: h: h.mac != null && h.ipv4 != null) topology.hosts;
  devicesWithMac = lib.filterAttrs (_name: d: d.mac != null && d.ipv4 != null) (
    topology.devices or { }
  );

  allReservations = hostsWithMac // devicesWithMac;

  # A DHCP reservation must live inside the subnet it is attached to, otherwise Kea refuses
  # to start ("address not within subnet") and the whole LAN loses DHCP. Every declared
  # subnet is a /24, so membership is decided on the /24 network part; that simplification is
  # asserted below rather than assumed.
  netOf =
    cidr:
    lib.concatStringsSep "." (lib.take 3 (lib.splitString "." (lib.head (lib.splitString "/" cidr))));
  inSubnet = cidr: ip: netOf cidr == netOf ip;

  # The pool a zone hands out: its own .100 to .200.
  poolIn = subnet: "${netOf subnet.cidr}.100 - ${netOf subnet.cidr}.200";

  reservationsIn =
    subnet:
    lib.mapAttrsToList (name: h: {
      hw-address = h.mac;
      ip-address = h.ipv4;
      hostname = name;
    }) (lib.filterAttrs (_name: h: inSubnet subnet.cidr h.ipv4) allReservations);

  reservations = lib.concatMap (entry: reservationsIn entry.config) dhcpSubnets;

  # --- Zone selection: one shared network, one class per zone (Kea ARM 8.4 / 8.6) --------------
  # Three logical subnets share a single physical link here, which is precisely the case Kea's
  # "shared networks" exist for (ARM 8.4: "more than one logical IP subnet deployed on the same
  # physical link ... called shared networks in Kea").
  # This is a correctness requirement, not tidiness. Without a shared network Kea selects exactly
  # one subnet for a directly connected client - the one its receiving interface's address falls
  # into (ARM 8.6) - and this interface carries an address of every zone at once, so one zone won
  # for every client, deterministically and by accident. Measured before this change: the access
  # point held a corp address and all six relays received corp pool addresses instead of their iot
  # reservations, no matter how the class tests were written.
  # Inside the shared network the class decides (ARM 8.4.2, 8.3.10): a subnet that names a class is
  # offered only to members of that class, and naming a class does *not* make a subnet preferred
  # over one that names none. Hence one class per served zone, the default zone's being the
  # complement of the declared ones rather than an absence.
  # The MAC test is the documented direct comparison against a hexadecimal literal
  # (`pkt4.mac == 0x…`). The earlier `hexstring(pkt4.mac,'')` string comparison was accepted
  # syntactically and never matched.
  macMatch = h: "pkt4.mac == 0x${lib.toLower (lib.replaceStrings [ ":" ] [ "" ] h.mac)}";

  membersOfZone = zone: lib.filter (h: h.zone == zone) (lib.attrValues allReservations);

  servedZones = lib.filter (zone: zone == cfg.defaultZone || membersOfZone zone != [ ]) dhcpZones;

  unservedZones = lib.subtractLists servedZones dhcpZones;

  declaredZones = lib.filter (zone: zone != cfg.defaultZone) servedZones;

  # One class per served zone, named after the zone - a subnet names its own class by naming itself,
  # so no mapping exists to keep in step. Kea evaluates classes in configuration order and
  # `member()` sees only classes assigned so far, so the declared zones come first and the complement
  # last: the pattern the ARM shows for `"test": "not member('reserved_class')"` (8.3.10).
  zoneClasses =
    map (zone: {
      name = zone;
      test = lib.concatMapStringsSep " or " (h: "(${macMatch h})") (membersOfZone zone);
    }) declaredZones
    ++ [
      {
        # The complement: whatever the inventory does not declare. The default zone cannot stay
        # classless, because a subnet without a class accepts every client (ARM 8.4.2) and would
        # then swallow the devices assigned to other zones.
        name = cfg.defaultZone;
        test =
          if declaredZones == [ ] then
            "member('ALL')"
          else
            lib.concatMapStringsSep " and " (zone: "not member('${zone}')") declaredZones;
      }
    ];
in
{
  options.my.features.system.networking.gateway = {
    enable = lib.mkEnableOption "Single-NIC Layer-3 Gateway, DHCP & NTP services (RFC 1812)";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "enp2s0";
      description = "Physical or primary network interface used for local subnet routing";
    };

    uplinkGateway = lib.mkOption {
      type = lib.types.str;
      default = "10.10.10.1";
      description = "Next-hop router/modem IP for WAN uplink (e.g. FRITZ!Box)";
    };

    routedZones = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "corp"
        "iot"
      ];
      description = ''
        Zones this host routes between. Each one contributes the router address declared for it by
        `my.topology.subnets.<zone>.gateway`: an address inside that zone, added to the interface
        and handed out as the DHCP router. A gateway outside its subnet cannot be used at all.
      '';
    };

    enableRouting = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable kernel IP forwarding and NAT/masquerade for inter-subnet and WAN transit";
    };

    enableDhcp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable declarative Kea DHCPv4 server";
    };

    defaultZone = lib.mkOption {
      type = lib.types.str;
      default = "corp";
      description = ''
        Zone that receives clients whose MAC the inventory does not declare. Its subnet is bound to
        the complement class - the clients belonging to no other zone - rather than left classless,
        because a subnet without a client class accepts every client and naming a class does not
        make a subnet preferred (Kea ARM 8.4.2). A declared device therefore lands in the zone its
        inventory entry names, whatever the order of the subnets.
      '';
    };

    enableNtp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Chrony NTP server for local network devices";
    };
  };

  config = lib.mkIf cfg.enable {
    # Every reservation must land inside a declared subnet; one that does not would either be
    # dropped silently or make Kea refuse to start (taking the whole LAN's DHCP down with it).
    assertions = [
      {
        assertion =
          builtins.length reservations == builtins.length (lib.mapAttrsToList (_: h: h) allReservations);
        message = ''
          Gateway: at least one DHCP reservation falls outside every declared subnet, so it
          would be dropped (or make Kea refuse to start). Check the ipv4 values in
          my.topology.hosts / my.topology.devices against my.topology.subnets.
        '';
      }
      {
        assertion = builtins.all (entry: entry.config.gateway != null) dhcpSubnets;
        message = ''
          Gateway: a zone served by DHCP declares no gateway, so its clients would receive no
          router. Set my.topology.subnets.<zone>.gateway - it has to live inside that zone.
        '';
      }
      {
        # Two inventory entries with the same MAC would pull one client into two classes, and
        # nothing would say which zone won.
        assertion =
          builtins.length (lib.attrValues allReservations)
          == builtins.length (lib.unique (map (h: lib.toLower h.mac) (lib.attrValues allReservations)));
        message = "Gateway: two entries in my.topology declare the same MAC address; every device must be inventarised exactly once.";
      }
      {
        # Without the default zone being served, an undeclared client would receive no lease at all.
        assertion = lib.elem cfg.defaultZone dhcpZones;
        message = "Gateway: defaultZone '${cfg.defaultZone}' is not among the zones served by DHCP (uplinkZone plus routedZones), so undeclared clients would get no address.";
      }
      {
        # A subnet without a class accepts every client, and naming a class does not make a subnet
        # preferred over one that names none (Kea ARM 8.4.2). A served zone without its own class
        # would therefore keep answering for devices the inventory assigned elsewhere, which is
        # exactly the defect this replaces.
        assertion =
          lib.sort (a: b: a < b) (map (class: class.name) zoneClasses)
          == lib.sort (a: b: a < b) (map (entry: entry.zone) dhcpSubnets);
        message = "Gateway: every served zone needs exactly one client class and nothing else; a subnet without its own class accepts clients of every other zone.";
      }
    ];

    # A zone that is routed but has no inventarised device is not served (see servedZones). That is
    # reported rather than asserted: it is a statement about the config being thinner than intended,
    # not a state that must block a deployment.
    warnings = lib.optional (cfg.enableDhcp && unservedZones != [ ]) (
      "Gateway: ${toString (builtins.length unservedZones)} routed zone(s) have no inventarised device and are therefore not served by DHCP: ${lib.concatStringsSep ", " unservedZones}. Undeclared clients receive addresses from the default zone '${cfg.defaultZone}'."
    );

    # 1. Kernel Layer-3 Routing & Forwarding
    boot.kernel.sysctl = lib.mkIf cfg.enableRouting {
      "net.ipv4.ip_forward" = 1;
      # Anti-spoofing loose mode for routing between multi-homed/mesh interfaces
      "net.ipv4.conf.all.rp_filter" = lib.mkForce 2;
      "net.ipv4.conf.default.rp_filter" = lib.mkForce 2;
    };

    # 2. Firewall: Allow DHCP (67/udp), NTP (123/udp), and DNS (53/udp+tcp) locally
    # 2b. A routed zone's gateway has to live inside that zone, so this host carries one address
    # per routed zone (the topology declares which one).
    networking.interfaces.${cfg.interface}.ipv4.addresses = lib.concatMap (
      zone:
      let
        subnet = topology.subnets.${zone};
      in
      lib.optional (subnet.gateway or null != null) {
        address = subnet.gateway;
        prefixLength = lib.toInt (builtins.elemAt (lib.splitString "/" subnet.cidr) 1);
      }
    ) cfg.routedZones;

    # 2c. Transit for the routed zones. Without this the kernel drops the packets in FORWARD even
    # though ip_forward and the NAT rule are in place. Zones the trust model marks untrusted
    # (iot, guest) stay excluded, which is the point of having them.
    networking.firewall.extraForwardRules = lib.concatMapStrings (
      zone:
      let
        subnet = topology.subnets.${zone};
        trusted = subnet.trustLevel != "iot" && subnet.trustLevel != "guest";
      in
      lib.optionalString (trusted && subnet.gateway != null) "ip saddr ${subnet.cidr} accept\n"
    ) cfg.routedZones;

    networking.firewall = {
      allowedUDPPorts = lib.flatten [
        (lib.optional cfg.enableDhcp 67)
        (lib.optional cfg.enableNtp 123)
      ];
    };

    # Masquerade (and permit forwarding for) the trusted zones that route through this host.
    # Declared through the nat module: it flushes and rebuilds its chains on every firewall reload,
    # so this describes state instead of accumulating rules - the previous extraCommand appended
    # another identical MASQUERADE on every activation.
    #
    # `internalIPs` is what actually generates the rules. With an empty list the module emits
    # nothing at all, which is how a refactor that looked clean silently removed the NAT for the
    # whole house. Only zones the trust model allows to reach the uplink are listed; iot and guest
    # stay isolated.
    networking.nat = lib.mkIf cfg.enableRouting {
      enable = true;
      externalInterface = cfg.interface;
      internalIPs = map (zone: topology.subnets.${zone}.cidr) (
        lib.filter (
          zone: topology.subnets.${zone}.trustLevel != "iot" && topology.subnets.${zone}.trustLevel != "guest"
        ) cfg.routedZones
      );
    };

    # 3. Declarative DHCP Server (Kea DHCPv4)
    services.kea.dhcp4 = lib.mkIf cfg.enableDhcp {
      enable = true;
      settings = {
        interfaces-config = {
          interfaces = [ cfg.interface ];
        };

        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };

        valid-lifetime = 86400; # 24h lease
        renew-timer = 43200; # 12h renew
        rebind-timer = 75600;

        option-data = [
          {
            name = "domain-name-servers";
            # Derived, and ours alone: no uplink fallback, because a client that fell back to the
            # router's resolver would get public answers and silently miss everything internal.
            data = lib.concatStringsSep ", " topology.resolvers;
          }
          {
            name = "domain-name";
            data = "lan.${topology.domain}";
          }
          {
            name = "ntp-servers";
            data = topology.hosts.${topology.lanRouter}.ipv4;
          }
        ];

        # One class per served zone. The parameter is the `client-classes` list; the older
        # `client-class` string is deprecated and Kea reports it on every start
        # (DHCPSRV_CLIENT_CLASS_DEPRECATED).
        client-classes = map (class: {
          inherit (class) name test;
        }) zoneClasses;

        # All served subnets sit in one shared network, because they share one physical link: that is
        # what makes Kea consider more than one of them for a client, and therefore what makes the
        # classes decide at all. `interface` at this level is the documented way to say that the
        # network is reachable directly rather than through relays (Kea ARM 8.4).
        #
        # Each subnet then carries the zone's CIDR, a pool inside it, the zone's own router (which by
        # construction lives inside it), the reservations that fall into it, and its class - every
        # subnet names one, the default zone included.
        shared-networks = [
          {
            name = "shared-${cfg.interface}";
            interface = cfg.interface;
            subnet4 = lib.imap0 (index: entry: {
              id = index + 1;
              subnet = entry.config.cidr;
              pools = [
                { pool = poolIn entry.config; }
              ];
              option-data = [
                {
                  name = "routers";
                  data = entry.config.gateway;
                }
              ];
              reservations = reservationsIn entry.config;
              client-classes = [ entry.zone ];
            }) dhcpSubnets;
          }
        ];
      };
    };

    # 4. Chrony NTP Server
    services.chrony = lib.mkIf cfg.enableNtp {
      enable = true;
      servers = [
        "0.de.pool.ntp.org"
        "1.de.pool.ntp.org"
        "time.cloudflare.com"
      ];
      extraConfig = ''
        # Serve time to local RFC 1918 supernet
        allow 10.10.0.0/16
        # Allow immediate time synchronization on startup
        makestep 1.0 3
      '';
    };
  };
}
