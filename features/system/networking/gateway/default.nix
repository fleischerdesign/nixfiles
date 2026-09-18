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

  reservations = lib.mapAttrsToList (name: h: {
    hw-address = h.mac;
    ip-address = h.ipv4;
    hostname = name;
  }) allReservations;
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
    # 1. Kernel Layer-3 Routing & Forwarding
    boot.kernel.sysctl = lib.mkIf cfg.enableRouting {
      "net.ipv4.ip_forward" = 1;
      # Anti-spoofing loose mode for routing between multi-homed/mesh interfaces
      "net.ipv4.conf.all.rp_filter" = lib.mkForce 2;
      "net.ipv4.conf.default.rp_filter" = lib.mkForce 2;
    };

    # 2. Firewall: Allow DHCP (67/udp), NTP (123/udp), and DNS (53/udp+tcp) locally
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
            reservations = reservations;
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
                data = cfg.dnsServer; # hom-srv-01 routes corp traffic
              }
            ];
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
                data = cfg.dnsServer; # hom-srv-01 acts as IoT gateway
              }
            ];
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
