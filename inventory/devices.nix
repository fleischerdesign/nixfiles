# inventory/devices.nix - every non-NixOS device of the site, the single authoritative declaration.
#
# Composed explicitly by lib/mk-system.nix, never auto-discovered; same extension policy as
# inventory/subnets.nix. A device's `zone` names a subnet of that file, not a trust level.
# Default IoT devices conforming to RFC 1178 Enterprise Taxonomy.
_: {
  my.topology.devices = {
    # Peripheral hardware that is not a microcontroller.
    hom-prn-01 = {
      zone = "iot";
      mac = "80:ce:62:8a:7c:06"; # HP MFP, hostname hp8a7c05; leases its iot address from Kea
      ipv4 = "10.10.30.19";
      description = "HP Multifunktionsdrucker/Scanner (hp8a7c05), iot-Zone";
      # The one thing a mesh member may use on this device: IPP. Its web interface (80/443) is
      # deliberately *not* declared - it stays reachable inside the LAN, where the segment is flat and
      # no rule of ours applies anyway, and it is closed from the mesh, which is where the exposure
      # would otherwise grow without anyone deciding it. Printing is the household's use case: the
      # servers and the family's own devices, not the cloud.
      endpoints.ipp = {
        port = 631;
        protocol = "tcp";
        from = [
          "infra"
          "corp"
        ];
        description = "Drucken aus dem Mesh (Server und Haushalt) - nicht aus der Cloud-Zone";
      };
    };
    # Enterprise Relais-Aktoren (Sonoff Basic ESP8266 Inline-Relais)
    #
    # They declare no endpoint, and that is a decision rather than an omission: the ESPHome dashboard
    # that talks to them runs on `hom-srv-01`, which shares their segment, so its traffic is never
    # routed; and a relay's API reachable over the mesh would be reachable by every member. Nothing
    # needs it, so nothing may use it.
    hom-rly-01 = {
      zone = "iot";
      ipv4 = "10.10.30.11";
      mac = "8c:ce:4e:0c:d7:98";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Arbeitszimmer Relais";
    };

    hom-rly-02 = {
      zone = "iot";
      ipv4 = "10.10.30.12";
      mac = "70:03:9f:64:8e:b0";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Bad Relais";
    };

    hom-rly-03 = {
      zone = "iot";
      ipv4 = "10.10.30.13";
      mac = "e8:68:e7:44:b3:a1";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Ender 3D-Drucker Relais";
    };

    hom-rly-04 = {
      zone = "iot";
      ipv4 = "10.10.30.14";
      mac = "8c:ce:4e:0c:e2:50";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Fernseher Deckenlampe";
    };

    hom-rly-06 = {
      zone = "iot";
      ipv4 = "10.10.30.16";
      mac = "8c:ce:4e:0c:e1:70";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Küche Relais";
    };

    hom-rly-07 = {
      zone = "iot";
      ipv4 = "10.10.30.17";
      mac = "8c:ce:4e:0c:da:e5";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Schlafzimmer Relais";
    };

    hom-rly-08 = {
      zone = "iot";
      ipv4 = "10.10.30.18";
      mac = "8c:ce:4e:0c:de:cb";
      platform = "esp8266";
      board = "esp01_1m";
      description = "Sofa Relais";
    };
  };
}
