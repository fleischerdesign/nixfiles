# features/system/networking/gateway/default.nix
# Single-NIC Router-on-a-Stick Gateway & Network Services (RFC 1812).
# Declares central DHCP (Kea), NTP (Chrony), and Layer-3 IPv4 Forwarding/NAT
# completely driven by `config.my.topology`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.gateway;
  topology = config.my.topology;

  # Subnet definitions from topology
  infraSubnet = topology.subnets.infra or null;
  corpSubnet = topology.subnets.corp or null;
  iotSubnet = topology.subnets.iot or null;

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

  allSubnets = lib.filter (s: s != null) [
    infraSubnet
    corpSubnet
    iotSubnet
  ];

  reservationsIn =
    subnet:
    lib.mapAttrsToList (name: h: {
      hw-address = h.mac;
      ip-address = h.ipv4;
      hostname = name;
    }) (lib.filterAttrs (_name: h: inSubnet subnet.cidr h.ipv4) allReservations);

  reservations = lib.concatMap reservationsIn allSubnets;
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

    dnsServer = lib.mkOption {
      type = lib.types.str;
      default = "10.10.10.10";
      description = "Primary DNS server handed out via DHCP (typically hom-srv-01 Blocky instance)";
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
    ];

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
      extraCommands = lib.optionalString cfg.enableRouting ''
        # NAT masquerade for outbound traffic leaving via the uplink interface
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o ${cfg.interface} -j MASQUERADE || true
      '';
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
            data = "${cfg.dnsServer}, ${cfg.uplinkGateway}";
          }
          {
            name = "domain-name";
            data = "lan.${topology.domain}";
          }
          {
            name = "ntp-servers";
            data = cfg.dnsServer;
          }
        ];

        # Each zone gets its own router address (inside that zone). The infra zone is served by
        # the uplink itself, the others by this host.
        subnet4 = [
          {
            id = 1;
            subnet = if infraSubnet != null then infraSubnet.cidr else "10.10.10.0/24";
            pools = [
              { pool = "10.10.10.100 - 10.10.10.200"; }
            ];
            option-data = [
              {
                name = "routers";
                data = cfg.uplinkGateway;
              }
            ];
            reservations = reservationsIn (
              if infraSubnet != null then infraSubnet else (builtins.head allSubnets)
            );
          }
          {
            id = 2;
            subnet = if corpSubnet != null then corpSubnet.cidr else "10.10.20.0/24";
            pools = [
              { pool = "10.10.20.100 - 10.10.20.200"; }
            ];
            option-data = [
              {
                name = "routers";
                data =
                  if topology.subnets.corp.gateway != null then topology.subnets.corp.gateway else cfg.dnsServer;
              }
            ];
            reservations = if corpSubnet != null then reservationsIn corpSubnet else [ ];
          }
          {
            id = 3;
            subnet = if iotSubnet != null then iotSubnet.cidr else "10.10.30.0/24";
            pools = [
              { pool = "10.10.30.100 - 10.10.30.200"; }
            ];
            option-data = [
              {
                name = "routers";
                data = if topology.subnets.iot.gateway != null then topology.subnets.iot.gateway else cfg.dnsServer;
              }
            ];
            reservations = if iotSubnet != null then reservationsIn iotSubnet else [ ];
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
