# inventory/hosts.nix - every node of the site, the single authoritative declaration.
#
# Composed explicitly by lib/mk-system.nix, never auto-discovered; same extension policy as
# inventory/subnets.nix. A host's `zone` names a subnet of that file, not a trust level: two
# zones may share a trust level, and an unknown zone fails the build (asserted in the topology
# schema). Naming follows RFC 1178 Enterprise Taxonomy.
_: {
  # Default host registry conforming to RFC 1178 Enterprise Taxonomy
  my.topology.hosts = {
    cld-edge-01 = {
      zone = "mesh";
      ipv4 = "173.249.22.211";
      gateway = "173.249.22.1";
      interface = "eth0";
      wireguardIpv4 = "10.10.100.1";
      wireguardIpv6 = "fd10:1000:100::1";
      wireguardPublicKey = "xaW5sos7b7wPXsjl4U6UqsaHl9l+Y1F013DDJ4kioEg=";
      wireguardRelay = true;
      hostType = "server";
    };

    cld-ops-01 = {
      zone = "mesh";
      ipv4 = "37.114.55.91";
      gateway = "37.114.55.1";
      interface = "eth0";
      wireguardIpv4 = "10.10.100.2";
      wireguardIpv6 = "fd10:1000:100::2";
      wireguardPublicKey = "DBU0HRrBeIXZFokauPXfsYA3i7feCov154VbkAdwlTM=";
      wireguardRelay = true;
      hostType = "server";
    };

    hom-srv-01 = {
      zone = "infra";
      ipv4 = "10.10.10.10";
      # No per-host gateway: `subnets.infra.gateway` is the single declaration for this zone. The
      # field survives only as the override for hosts whose uplink is not a zone gateway at all -
      # the VPS hosts, which sit behind their provider's router.
      gateway = null;
      interface = "enp2s0";
      wireguardIpv4 = "10.10.100.10";
      wireguardIpv6 = "fd10:1000:100::10";
      wireguardPublicKey = "j80spw+2+Ojz51aKAytPdCZwFOc64yNOR05rAcXOESE=";
      hostType = "server";
    };

    hom-wrk-01 = {
      zone = "corp";
      ipv4 = "10.10.20.10";
      # No per-host gateway: the zone's gateway (10.10.20.1) is the one that lives inside the
      # subnet and is therefore the only one that can be installed as a default route.
      gateway = null;
      interface = "enp0s31f6";
      wireguardIpv4 = "10.10.100.20";
      wireguardIpv6 = "fd10:1000:100::20";
      wireguardPublicKey = "y9CMim/6IWIKdIztKJQh5BR7R2ygjYwCjjEvgJQSLT0=";
      hostType = "workstation";
    };

    mob-nb-01 = {
      zone = "corp";
      ipv4 = null; # Roaming DHCP
      gateway = null;
      wireguardIpv4 = "10.10.100.30";
      wireguardIpv6 = "fd10:1000:100::30";
      wireguardPublicKey = "J+PERS3HY0OcfXKk4qFnJWtgLy4afh3cXX8fkuKelx0=";
      hostType = "client";
    };

    # A phone joins the mesh as a client node, not a managed host: it has an overlay identity and no
    # NixOS configuration. `mob-nb-01` is the same class of node; this one's WireGuard configuration
    # is rendered from the topology and its SOPS key instead of `networking.wireguard.interfaces`.
    # The name follows `<class>-<role>-<nn>` (docs/architecture.md §2), not a person.
    mob-ph-01 = {
      zone = "corp";
      ipv4 = null; # Roaming: no LAN address, so it carries every delivered zone over the mesh.
      gateway = null;
      wireguardIpv4 = "10.10.100.40";
      wireguardIpv6 = "fd10:1000:100::40";
      wireguardPublicKey = "33yImKTdRMyeM8yYgabBLbZ1xLIMife6CGsSMCicmjo=";
      hostType = "client";
      # The push transport, kept off the tunnel: measured 2026-09-22, the phone's VPN network carries
      # no `INTERNET` capability (it is a split tunnel, so it has routes, not a default route), and an
      # app that requires that capability does not use such a network - which is how notifications stop
      # being rebuilt while the tunnel is up and arrive in a burst once it is switched off. The same
      # exclusion was needed on Tailscale for the same reason.
      excludedApplications = [
        "com.google.android.gms"
        "com.google.android.gsf"
      ];
    };

    # Embedded targets as specified in docs/embedded.md
    hom-rt-01 = {
      zone = "infra";
      ipv4 = "10.10.10.1";
      hostType = "embedded";
    };

    hom-ap-01 = {
      zone = "infra";
      ipv4 = "10.10.10.20";
      mac = "7c:f1:7e:6a:b0:82"; # wired MAC: leases the declared address from Kea
      hostType = "embedded";
    };
  };
}
