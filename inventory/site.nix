# inventory/site.nix - site-wide naming and network service assignments.
#
# These values describe this deployment, not the topology schema or an individual host. This
# module is composed explicitly with the host, subnet and device inventories.
_: {
  my.topology = {
    domain = "vyrx.de";
    ingressHost = "cld-edge-01";
    lanRouter = "hom-srv-01";
    upstreamRouter = "hom-rt-01";
    accessPoint = "hom-ap-01";
    primaryWireguardHub = "cld-edge-01";
    defaultDhcpZone = "corp";
    ntpZones = [
      "infra"
      "corp"
      "iot"
    ];
    resolverHosts = [
      "hom-srv-01"
      "cld-edge-01"
    ];
    wifi.ssid = "VYRX";
  };
}
