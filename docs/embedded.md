# Embedded devices and agentless targets

> **Model:** the Nix store and the compiler stay on the build machine; the device receives its
> configuration or its firmware, never NixOS.
>
> These are the devices that cannot run the fleet's operating system, and the reconcilers that keep them
> in their declared state. What they all share is one interface - `my.topology` - and one rule: the
> device holds nothing that the repository does not know.

## 1. The model

```
        my.topology + secrets (single source of truth)
                          │
        compile on the build machine (store stays there)
                          │
       ┌──────────────────┼───────────────────┬──────────────────┐
       ▼                  ▼                   ▼                  ▼
  NixOS host        access point         router            microcontroller
  SSH + switch      vendor web API       TR-064 API        OTA firmware
```

A device is declared once (`my.topology.devices`, or `hosts` for the router and the access point) with
its zone, its address and its MAC. From that declaration follow the DHCP reservation, the name in the
LAN DNS, the firewall treatment and the firmware or settings that the reconciler pushes.

**Devices with a MAC and an address become reservations.** A device with an address but no MAC cannot
be one - it would be a reservation outside every declared subnet, which makes Kea refuse to start - and
that is why the printer carried no MAC until it was given one that belongs in the IoT zone.

## 2. The inventory

| Device | Type | Zone | Address | Configuration |
|---|---|---|---|---|
| `hom-ap-01` | TP-Link RE330 access point | `infra` | `10.10.10.20` | vendor web API via `tplinkrouterc6u` |
| `hom-rt-01` | AVM FRITZ!Box | `infra` | `10.10.10.1` | TR-064 (SOAP over HTTPS) |
| `hom-rly-01` … `hom-rly-08` | Sonoff Basic (ESP8266) | `iot` | `10.10.30.11` … `.18` | ESPHome firmware, flashed over OTA |
| `hom-prn-01` | HP multifunction printer | `iot` | `10.10.30.19` | none - a DHCP reservation, plus a declared IPP endpoint (below) |

Nothing else exists. There are no Zigbee bridges, no managed switches, no ESP32 sensors and no WLED
strips in this fleet; the previous version of this document specified three of them.

## 3. Access point

The RE330 runs **closed vendor firmware**: no SSH, no OpenWrt, therefore no UCI and no config file to
render. The reconciler speaks the encrypted web API (RSA/AES handshake) through `tplinkrouterc6u`.

- **One SSID, both bands.** The desired state declares `VYRX` on 2.4 and 5 GHz so clients can use one
  identity and steer themselves. It is derived from `my.topology.wifi.ssid`, which is also what the
  microcontrollers store - one name, one source.
- **Addressing is not the access point's.** It is a Layer-2 bridge; DHCP, DNS, NTP and routing come
  from `hom-srv-01`, and the box's own DHCP was turned off during the cutover.
- **The reconciler derives its target from the declared address.** It used to read a migration address
  from the topology; with that gone it addresses `ipv4`, which is where the device answers (measured).
- **Run it directly, not through `nod`.** Both agentless reconcilers reject the `switch` action
  argument - see the hazards in [operations.md](operations.md) §10.

## 4. Router

The FRITZ!Box is a modem with a LAN interface: uplink and nothing else. It is configured over TR-064
from `hom-srv-01`. Where the API has no action - the announced DNS and the IPv6 settings - the value
is set in the web interface and the table below records it; the API's silence is a fact about the
device, not a licence to change it by hand later.

| Setting | Declared | Why |
|---|---|---|
| DHCP | **off** | `hom-srv-01` is the only DHCP server on the segment; two would be a race |
| port forwardings | **none** | nothing is published from the home directly - ingress happens at the edge, and the LAN is reached over the mesh |
| DNS | not settable by the API | the fleet's resolvers are handed out by Kea instead |
| IPv6 in the home network | **off** - no router advertisements, no DHCPv6 (set by hand 2026-09-21) | while it was on, the box announced itself as a resolver over RDNSS (RFC 5006) and DHCPv6, so a device at home learned a second resolver - one that answers our public names with the **public** address, and that no rule can reach while the box sits on the same flat segment. The LAN is IPv4-only by decision and the IPv6 uplink was never usable (measured: an IPv6 curl from a LAN host has never succeeded). Measured after the change: a router solicitation is answered by nobody, and the hosts keep `10.10.10.10` as their only resolver |
| Wi-Fi | the box radiates nothing the fleet uses | the access point is the single Wi-Fi plane |

The engine is **diff-only for anything but these**: it reports what the device has and writes the
desired state, and it refuses a non-empty port-forwarding list rather than guessing - see
[operations.md](operations.md) §10 for the hazard that comes with applying it.

## 5. Microcontrollers

ESP8266 relays (Sonoff Basic) switching mains circuits. The firmware is compiled hermetically by Nix -
`templates/sonoff-basic.nix` plus the per-device declaration in `devices/switches.nix` - and pushed
over the air by `esphome-sync-<device>`.

- **Only devices that are both declared and known to the template are managed**: the engine filters on
  `device.mac != null && specs ? <name>`, so an entry in the topology without a matching declaration is
  ignored rather than guessed at.
- **The address comes from the reservation.** A device that is not there yet is flashed at whatever
  address it currently answers on (`--device`), which is how the six relays were moved into their IoT
  addresses.
- **No dashboard.** ESPHome removed its built-in dashboard upstream; the module deliberately runs none,
  because a unit that dies with "the built-in dashboard has been removed" takes an activation's exit
  code with it. The fleet is managed through the CLI and the generated packages.
- **Secrets never touch the store.** The engine assembles `secrets.yaml` in a private temporary
  directory, flashes, and deletes it. The compiled firmware contains the credentials; the build host
  does not retain them.
- **The firmware carries one network.** It used to carry a second, legacy SSID as a fallback; that name
  is not radiated any more (measured by scan), so it was removed from the configuration. Running devices
  keep it until the next flash, which changes nothing at runtime.
- **They declare no endpoint, and that is the decision.** A device in a carried zone is reachable from
  the mesh, so its policy has to be written down somewhere - and nowhere is more honest than the device
  itself (`my.topology.devices.<name>.endpoints`). The relays offer nothing a member of the mesh needs:
  the ESPHome tooling that talks to them runs on `hom-srv-01`, which shares their segment, so its traffic
  is never routed. Their API (`6053`) was reachable from every mesh node before that rule existed;
  measured after, it is closed.

## 6. What the mesh may use

The printer is the one device in this fleet that a roaming member legitimately needs, so it declares
one endpoint: IPP on `631`, for the trust levels `infra` and `corp`. The host that routes the zone
(`hom-srv-01`) turns that declaration into firewall rules - the same lattice the fleet's own services
use, applied to forwarding instead of input - and everything else on the device stays closed from the
mesh. Its web interface is a good example of why that matters: it is a full administration surface with
no authentication worth the name, and inside the LAN it is reachable anyway (one flat segment), while
from the mesh it is now not.

The audit holds both halves: a declared port has to answer from the hub a roaming client uses, and a
port nobody declared has to refuse. A refusal is the only evidence that the closed default is real.

## 7. The DNS zone as a target

Cloudflare is not a device, but it is reconciled the same way: the zone is a function of the
configuration.

- The desired state is generated from `my.topology` and the contract projections - per name, never a
  wildcard. The apex and the wildcard belong to Cloudflare's own Universal SSL, which is also why
  certificates are issued per name ([architecture.md](architecture.md) §5.3).
- The engine compares and writes; `--prune` deletes only records **it** owns, recognised by its own
  comment vocabulary. A record written by something else - a dynamic-DNS client, an ACME challenge, a
  human - is unreachable by construction, which is a feature: the reconciler cannot delete what it did
  not create.
- Records are `proxied: false`: the mesh, SSH and CrowdSec bans all depend on the real address.

## 8. What follows from a single declaration

Declaring a device is enough - the rest is projection:

| Effect | Producer |
|---|---|
| DHCP reservation in its zone | the gateway, from `mac` + `ipv4` |
| Client class membership, so it lands in the right zone | the gateway, from `zone` |
| Name in the LAN DNS | the naming projection |
| Firewall treatment per trust level | the zone's trust level |
| Reachability for roaming clients | the mesh, if the zone is delivered by the LAN gateway |

A device in `iot` that has no MAC is not isolated from anything - it simply does not exist as far as the
gateway is concerned, and will take a default-zone lease. That is the rule, not a fallback:
uninventarised hardware gets an address from the default zone and nothing else.
