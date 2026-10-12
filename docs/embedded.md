# Embedded devices and agentless targets

> **Model:** the Nix store and the compiler stay on the build machine; the device receives its configuration
> or its firmware, never NixOS. What all these devices share is one interface - `my.topology` - and one rule:
> the device holds nothing the repository does not know.

## 1. The model

```
        my.topology + secrets (single source of truth)
                          |
        compile on the build machine (store stays there)
                          |
       +------------------+-------------------+------------------+
       v                  v                   v                  v
  NixOS host        access point         router            microcontroller
  SSH + switch      vendor web API       TR-064 API        OTA firmware
```

A device is declared once (`my.topology.devices`, or `hosts` for the router and the access point) with its
zone, its address and its MAC. From that declaration follow the DHCP reservation, the name in the LAN DNS,
the firewall treatment and the firmware or settings the reconciler pushes. A device with an address but no
MAC cannot become a reservation - it would fall outside every declared subnet and Kea would refuse to start -
which is why the printer carries one.

## 2. The inventory

| Device | Type | Zone | Address | Configuration |
|---|---|---|---|---|
| `hom-ap-01` | TP-Link RE330 access point | `infra` | `10.10.10.20` | vendor web API via `tplinkrouterc6u` |
| `hom-rt-01` | AVM FRITZ!Box | `infra` | `10.10.10.1` | TR-064 (SOAP over HTTPS) |
| `hom-rly-01` … `hom-rly-08` | Sonoff Basic (ESP8266) | `iot` | `10.10.30.11` … `.18` | ESPHome firmware, flashed over the air |
| `hom-prn-01` | HP multifunction printer | `iot` | `10.10.30.19` | a DHCP reservation and a declared IPP endpoint |

Nothing else exists: no Zigbee bridge, no managed switch, no ESP32 sensor, no LED strip.

## 3. Access point

The RE330 runs closed vendor firmware: no SSH, no OpenWrt, therefore no UCI and no configuration file to
render. The reconciler speaks the encrypted web API (RSA/AES handshake) through `tplinkrouterc6u`.

- **One SSID, both bands.** The desired state declares the fleet SSID on 2.4 and 5 GHz so clients keep one
  identity and steer themselves. It derives from `my.topology.wifi.ssid`, which is also what the
  microcontrollers store: one name, one source.
- **Addressing is not the access point.** It is a Layer-2 bridge; DHCP, DNS, NTP and routing come from
  `hom-srv-01`.
- **Run it directly, not through `nod`:** both agentless reconcilers reject the `switch` action argument (see
  the hazards in [operations.md](operations.md) §7).

## 4. Router

The FRITZ!Box is a modem with a LAN interface: uplink and nothing else. It is configured over TR-064 from
`hom-srv-01`. Where the API has no action the value is set in the web interface, and the table records it -
the silence of the API is a fact about the device, not a licence to change it by hand later.

| Setting | Declared | Why |
|---|---|---|
| DHCP | **off** | `hom-srv-01` is the only DHCP server on the segment; two would be a race |
| port forwardings | **none** | nothing is published from the home directly - ingress happens at the edge, and the LAN is reached over the mesh |
| DNS | not settable by the API | the resolvers of the fleet are handed out by Kea instead |
| IPv6 in the home network | **off** - no router advertisements, no DHCPv6 | while it was on, the box announced itself as a resolver over RDNSS and DHCPv6, so a device at home learned a second resolver that answers our public names with the **public** address, which no rule can reach on the same flat segment. The LAN is IPv4-only by decision |
| Wi-Fi | the box radiates nothing the fleet uses | the access point is the single Wi-Fi plane |

The engine is diff-only: it reports what the device has and writes the desired state, and it refuses a
non-empty port-forwarding list rather than guessing.

## 5. Microcontrollers

ESP8266 relays (Sonoff Basic) switch mains circuits. The firmware is compiled hermetically by Nix -
`templates/sonoff-basic.nix` plus the per-device declaration - and pushed over the air by
`esphome-sync-<device>`.

- **Only declared devices with a template are managed**: the engine filters on
  `device.mac != null && specs ? <name>`, so a topology entry without a matching declaration is ignored
  rather than guessed at.
- **A relay declares what it switches.** `relayKind` says whether the GPIO drives a lamp circuit - declared as
  a `light`, so Home Assistant shows a lamp - or mains power, like the 3D printer, which stays a `switch`.
  The same value picks the action the physical button calls, because ESPHome names an action after the domain
  of its entity; a lamp that stays a `switch` in the firmware can never be shown as one in Home Assistant.
- **A relay names two things.** `friendlyName` names the load and the entity names the function; the entity
  name is not optional, because ESPHome marks an entity carrying only an `id` as internal and it never reaches
  Home Assistant. Neither name carries a room - the room is the area, which the entity ID already starts with.
- **The address comes from the reservation.** A device that is not there yet is flashed at whatever address it
  currently answers on (`--device`).
- **No dashboard.** ESPHome removed its built-in dashboard upstream; the module runs none, because a unit that
  dies with that removes a whole activation with it.
- **Secrets never touch the store.** The engine assembles `secrets.yaml` in a private temporary directory,
  flashes, and deletes it. The firmware carries the credentials; the build host retains none.
- **No endpoint, deliberately.** A device in a carried zone is reachable from the mesh, so its policy is
  declared on the device (`my.topology.devices.<name>.endpoints`). The relays offer nothing a member of the
  mesh needs - the ESPHome tooling runs on `hom-srv-01`, which shares their segment - so their API port is
  closed to the mesh.

## 6. What the mesh may use

The printer is the one device a roaming member legitimately needs, so it declares one endpoint: IPP on `631`,
for the trust levels `infra` and `corp`. The host that routes the zone (`hom-srv-01`) turns that declaration
into firewall rules - the same lattice the services use, applied to forwarding instead of input - and
everything else on the device stays closed from the mesh. Its web interface is a full administration surface
with no authentication worth the name: inside the LAN it is reachable anyway, from the mesh it is not.

The audit holds both halves: a declared port must answer from the hub a roaming client uses, and a port
nobody declared must refuse. A refusal is the only evidence that the closed default is real.

## 7. The DNS zone as a target

Cloudflare is not a device, but it is reconciled the same way:

- the desired state is generated from `my.topology` and the contract projections, per name, never a wildcard;
  the apex and the wildcard belong to Cloudflare Universal SSL, which is why certificates are issued per name
  ([architecture.md](architecture.md) §5.3);
- the engine compares and writes, and `--prune` deletes only records **it** owns, recognised by its own
  comment vocabulary - a record written by something else (a dynamic-DNS client, an ACME challenge, a human)
  is unreachable by construction;
- records are `proxied: false`, because the mesh, SSH and CrowdSec bans all depend on the real address.

## 8. What follows from a single declaration

| Effect | Producer |
|---|---|
| DHCP reservation in its zone | the gateway, from `mac` + `ipv4` |
| Client class membership, so it lands in the right zone | the gateway, from `zone` |
| Name in the LAN DNS | the naming projection |
| Firewall treatment per trust level | the trust level of the zone |
| Reachability for roaming clients | the mesh, if the zone is delivered by the LAN gateway |

A device in `iot` that has no MAC is isolated from nothing - as far as the gateway is concerned it does not
exist and takes a default-zone lease. That is the rule, not a fallback: uninventarised hardware gets an
address from the default zone and nothing else.
