# apps/network-audit/default.nix - does the running fleet answer as its configurations say?
#
# Which path a host uses to the home door decides which plane the answer must come from, and the
# resolver's own projection says what that answer is.
#
# No expectation is written here. The projections of the contracts are the expectations, every value is
# baked in at build time, and the remote part is a quoted heredoc - which cannot expand anything
# locally, so a command can never run on the wrong machine.
{
  pkgs,
  lib,
  hostNames,
  self,
}:
let
  fleet = import ../lib/fleet.nix { inherit lib hostNames self; };
  inherit (fleet)
    cfgOf
    topology
    deployed
    addressOf
    ;

  resolverHost = lib.findFirst (name: (cfgOf name).my.features.services.dns.enable) null hostNames;
  answers = (cfgOf resolverHost).my.features.services.dns.answers;
  answerFor =
    name: plane:
    let
      match = lib.findFirst (answer: answer.name == "${name}." && answer.plane == plane) null answers;
    in
    if match == null then "NXDOMAIN" else match.address;

  probeName = "jellyfin.${topology.domain}";
  deviceFqdn = "${lib.head (lib.attrNames topology.devices)}.node.${topology.domain}";

  planes = [
    {
      path = "home";
      service = answerFor probeName "lan";
      device = answerFor deviceFqdn "lan";
    }
    {
      path = "away";
      service = answerFor probeName "overlay";
      device = answerFor deviceFqdn "overlay";
    }
  ];

  fleetTable =
    lib.concatMapStringsSep " " (host: "\"${host.name}|${host.address}|${host.meshInterface}\"")
      (
        map (name: {
          inherit name;
          address = addressOf name;
          meshInterface = (cfgOf name).my.features.system.networking.wireguard.interfaceName;
        }) deployed
      );

  # The home zones as `mask:network` pairs, so the path question ("does this host hold an address of a
  # home zone?") is answered the same way the dispatcher answers it: from the inventory, not from a list.
  zoneMasks = lib.concatMapStrings (
    zone:
    let
      cidr = topology.subnets.${zone}.cidr;
      octets = map lib.toInt (lib.splitString "." (builtins.head (lib.splitString "/" cidr)));
      length = lib.toInt (builtins.elemAt (lib.splitString "/" cidr) 1);
      # 2^32 - 2^(32-length): the mask of a prefix, built by multiplication because Nix has no shift
      mask = 4294967296 - (lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - length)));
      address = lib.foldl' (acc: octet: acc * 256 + octet) 0 octets;
    in
    " ${toString mask}:${toString (lib.bitAnd address mask)}"
  ) topology.lanZones;

  # --- device access over the mesh -------------------------------------------------------------------
  # A declaration is half a proof: it says what *should* be reachable, and the rule that carries it lives
  # on another host, inserted into a chain nobody reads. So the audit asks the hub a roaming client would
  # use - for every declared port, and for ports nobody declared. The second half is what shows the
  # default is closed rather than merely undocumented.
  primaryHub = (cfgOf (builtins.head hostNames)).my.features.system.networking.wireguard.primaryHub;
  hubAddress =
    if topology.hosts.${primaryHub}.wireguardIpv4 != null then
      topology.hosts.${primaryHub}.wireguardIpv4
    else
      topology.hosts.${primaryHub}.ipv4;
  # The level the probe speaks from. It decides what a *declared* port has to do: a device that declares
  # `from = ["infra" "corp"]` must answer a member of those levels and refuse everyone else, so a probe
  # from a `mesh` host is expected to be refused. Whether a *declaring* level reaches the device over the
  # mesh is a different question, and the phone answers it: it is a `corp` node off the LAN.
  hubTrustLevel =
    (topology.subnets.${topology.hosts.${primaryHub}.zone} or { }).trustLevel
      or topology.hosts.${primaryHub}.zone;
  carriedDevices = lib.filterAttrs (
    _: device: builtins.elem device.zone topology.announcedZones
  ) topology.devices;

  undeclaredProbePorts = [
    80
    443
    22
    6053
    9100
  ];
  deviceProbeTable =
    lib.concatMapStringsSep " "
      (entry: "\"${entry.label}|${entry.address}|${toString entry.port}|${entry.expectation}\"")
      (
        lib.concatLists (
          lib.mapAttrsToList (
            deviceName: device:
            let
              declared = map (endpoint: endpoint.port) (lib.attrValues device.endpoints);
            in
            map (endpoint: {
              label = "${deviceName}:${toString endpoint.port}/declared";
              address = device.ipv4;
              inherit (endpoint) port;
              expectation = if builtins.elem hubTrustLevel endpoint.from then "open" else "closed";
            }) (lib.attrValues device.endpoints)
            ++ map (port: {
              label = "${deviceName}:${toString port}/undeclared";
              address = device.ipv4;
              inherit port;
              expectation = "closed";
            }) (lib.filter (port: !(builtins.elem port declared)) undeclaredProbePorts)
          ) carriedDevices
        )
      );
in
pkgs.writeShellApplication {
  name = "network-audit";
  excludeShellChecks = [
    "SC2016" # the remote part is quoted on purpose: nothing may expand locally
    "SC2086" # word splitting inside the remote part is deliberate
    "SC2029" # the device probe is built locally on purpose: the address and port must expand here
  ];
  runtimeInputs = with pkgs; [
    openssh
    glibc.bin
    gnugrep
    gnused
    coreutils
    bash
    iproute2
    ndisc6
  ];
  text = ''
    set -uo pipefail

    KEY="''${NETWORK_AUDIT_KEY:-$HOME/.ssh/nixfiles-deploy-key}"
    SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

    PLANES=(
    ${
      lib.concatMapStrings (plane: "        \"${plane.path}|${plane.service}|${plane.device}\"\n") planes
    }      )

    fails=0
    checks=0

    expect() { # <what> <must be> <measured>
      checks=$((checks + 1))
      if [ "$2" = "$3" ]; then
        printf '  ok    %-40s %s\n' "$1" "$3"
      else
        printf '  FAIL  %-40s expected %s, measured %s\n' "$1" "$2" "$3"
        fails=$((fails + 1))
      fi
    }

    printf 'paths: home = holds an address of a home zone, away = only the mesh\n'

    for entry in ${fleetTable}; do
      IFS='|' read -r name address meshInterface <<< "$entry"
      printf '\n%s (%s)\n' "$name" "$address"

      measured=$(ssh "''${SSH_OPTS[@]}" "root@$address" 'bash -s' -- "$meshInterface" <<'REMOTE' 2>/dev/null || echo UNREACHABLE
        meshInterface="$1"
        ip2int() { local a b c d; IFS=. read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
        path=away
        for entry in ${zoneMasks}; do
          mask=''${entry%%:*}; net=''${entry#*:}
          for addr in $(ip -4 -o addr show 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){3}'); do
            [ $(( $(ip2int "$addr") & mask )) -eq "$net" ] && path=home
          done
        done
        printf 'path=%s\n' "$path"
        printf 'service=%s\n' "$(getent hosts ${probeName} 2>/dev/null | head -1 | cut -d' ' -f1)"
        printf 'device=%s\n' "$(getent hosts ${deviceFqdn} 2>/dev/null | head -1 | cut -d' ' -f1)"
        printf 'blocked=%s\n' "$(getent hosts doubleclick.net >/dev/null 2>&1 && echo no || echo yes)"
        printf 'peers=%s\n' "$(wg show "$meshInterface" latest-handshakes 2>/dev/null | wc -l)"
    REMOTE
      )

      if [ "$measured" = "UNREACHABLE" ]; then
        printf '  FAIL  %-40s the host did not answer over the mesh\n' "reachability"
        checks=$((checks + 1))
        fails=$((fails + 1))
        continue
      fi

      path=$(printf '%s\n' "$measured" | sed -n 's/^path=//p')
      got_service=$(printf '%s\n' "$measured" | sed -n 's/^service=//p')
      got_device=$(printf '%s\n' "$measured" | sed -n 's/^device=//p')
      blocked=$(printf '%s\n' "$measured" | sed -n 's/^blocked=//p')
      peers=$(printf '%s\n' "$measured" | sed -n 's/^peers=//p')

      row=""
      for candidate in "''${PLANES[@]}"; do
        [ "''${candidate%%|*}" = "$path" ] && row="$candidate"
      done

      if [ -z "$row" ]; then
        printf '  FAIL  %-40s %s\n' "has a path we know" "''${path:-none}"
        checks=$((checks + 1))
        fails=$((fails + 1))
        continue
      fi

      expect "${probeName} answered on that path" "$(printf '%s' "$row" | cut -d'|' -f2)" "''${got_service:-NXDOMAIN}"
      expect "${deviceFqdn} answered on that path" "$(printf '%s' "$row" | cut -d'|' -f3)" "''${got_device:-NXDOMAIN}"
      expect "the blocklist answers NXDOMAIN" "yes" "''${blocked:-unknown}"
      expect "the tunnel has peers" "yes" "$([ "''${peers:-0}" -ge 1 ] && echo yes || echo no)"
    done

    # --- device access over the mesh ----------------------------------------------------------
    # Asked where a roaming client asks from. A port declared for the prober's trust level has to
    # answer, and a port that was not declared for it - or not declared at all - has to refuse. A
    # refusal is the only evidence that the closed default is real; the *grant* side is what the phone
    # proves, because it is the only `corp` node that is off the LAN.
    printf '\nDevice access over the mesh (asked from ${primaryHub}, level ${hubTrustLevel}):\n'
    for entry in ${deviceProbeTable}; do
      IFS='|' read -r label address port expectation <<< "$entry"
      got=$(ssh "''${SSH_OPTS[@]}" "root@${hubAddress}" "timeout 3 bash -c 'exec 3<>/dev/tcp/$address/$port' 2>/dev/null && echo open || echo closed" 2>/dev/null || echo unreachable)
      expect "$label" "$expectation" "$got"
    done

    # --- what the home segment is told --------------------------------------------------------
    # Every device keeps a resolver a network once taught it (measured: a phone held the uplink
    # router's address for hours after it stopped announcing itself), so the way to keep a foreign
    # resolver out is that it is never announced. The probe is a router solicitation: on a segment we
    # route, nobody may answer it - the resolver's doors are the only resolvers that know our names.
    printf '\nAnnouncements on the home segment:\n'
    ip2int() { local a b c d; IFS=. read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
    lan_iface() {
      local _ dev _ cidr _ addr entry mask net
      while read -r _ dev _ cidr _; do
        [ -n "''${cidr:-}" ] || continue
        addr=''${cidr%/*}
        for entry in ${zoneMasks}; do
          mask=''${entry%%:*}; net=''${entry#*:}
          if [ $(( $(ip2int "$addr") & mask )) -eq "$net" ]; then echo "$dev"; return; fi
        done
      done < <(ip -4 -o addr show scope global 2>/dev/null)
    }
    iface=$(lan_iface)
    if [ -n "''${iface:-}" ]; then
      solicitation=$(timeout 8 rdisc6 -1 "$iface" 2>&1 || true)
      if printf '%s' "$solicitation" | grep -q 'from '; then
        printf '  FAIL  %-40s %s\n' "router advertisements on $iface" "somebody answered"
        checks=$((checks + 1)); fails=$((fails + 1))
      else
        expect "router advertisements on $iface" "nobody answers" "nobody answers"
      fi
    else
      printf '  skip  %-40s %s\n' "router advertisements" "this machine holds no address in a home zone"
    fi

    printf '\n%s checks, %s failed\n' "$checks" "$fails"
    [ "$fails" -eq 0 ]
  '';
}
