# lib/audit/default.nix - measures the fleet against what the inventory promises.
#
# The static check (`checks.network-invariants`) proves that the configurations agree with each other.
# This proves that the running hosts do what their configurations say, and the difference is not
# academic: a name answered from a door other than the one whose path the host is using is exactly how a
# home client ended up with overlay addresses and reached its printer through the relays.
#
# No expectation is written here. The path a host uses is measured (`ip route get <home door>`: the LAN
# or the tunnel), the planes the resolver answers are read from its own projection, and the two are
# required to agree. That is location-independent: a node abroad is judged on the path it actually has,
# not on where it usually sits.
{
  pkgs,
  lib,
  hostNames,
  self,
}:
let
  cfgOf = name: self.nixosConfigurations.${name}.config;
  reference = cfgOf (builtins.head hostNames);
  topology = reference.my.topology;

  homeDoor = topology.hosts.${topology.lanRouter}.ipv4;
  meshDoor = topology.hosts.${topology.lanRouter}.wireguardIpv4;

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

  # The home zones as `network:mask` pairs, so the probe can decide the path the same way the dispatcher
  # does: the host is at home when the interface that routes to the home door carries a home address.
  # Both read the same zones from the inventory; neither hardcodes an address.
  zoneMasks = lib.concatMapStrings (
    zone:
    let
      cidr = topology.subnets.${zone}.cidr;
      octets = map lib.toInt (lib.splitString "." (builtins.head (lib.splitString "/" cidr)));
      length = lib.toInt (builtins.elemAt (lib.splitString "/" cidr) 1);
      # 2^32 - 2^(32-length): the mask of a prefix, built from multiplication because Nix has no shift
      mask = 4294967296 - (lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - length)));
      address = lib.foldl' (acc: octet: acc * 256 + octet) 0 octets;
    in
    " ${toString mask}:${toString (lib.bitAnd address mask)}"
  ) topology.lanZones;

  # The path decides the plane, so the expectation follows the path.
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

  deployed = lib.filter (name: topology.hosts ? ${name}) hostNames;
  fleet = map (name: {
    inherit name;
    address =
      if topology.hosts.${name}.wireguardIpv4 != null then
        topology.hosts.${name}.wireguardIpv4
      else
        topology.hosts.${name}.ipv4;
  }) deployed;

  audit = pkgs.writeShellApplication {
    name = "network-audit";
    excludeShellChecks = [
      "SC2016" # the remote part is quoted on purpose: nothing may expand locally
      "SC2086" # word splitting inside the remote part is deliberate
    ];
    runtimeInputs = with pkgs; [
      openssh
      glibc.bin
      gnugrep
      gnused
      coreutils
    ];
    text = ''
      set -uo pipefail

      KEY="''${NETWORK_AUDIT_KEY:-$HOME/.ssh/nixfiles-deploy-key}"
      SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)

      # <path>|<what ${probeName} must answer on that path>|<what ${deviceFqdn} must answer>
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

      printf 'paths: home = reaches %s over a home address, away = only through the mesh (%s)\n' "${homeDoor}" "${meshDoor}"

      for entry in ${lib.concatMapStringsSep " " (host: "\"${host.name}|${host.address}\"") fleet}; do
        IFS='|' read -r name address <<< "$entry"
        printf '\n%s (%s)\n' "$name" "$address"

        measured=$(ssh "''${SSH_OPTS[@]}" "root@$address" 'bash -s' <<'REMOTE' 2>/dev/null || echo UNREACHABLE
          ip2int() { local a b c d; IFS=. read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
          # at home = this host holds an address of a home zone at all: the zone gateway reaches every
          # other home zone, and the host that routes them holds them itself
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
          printf 'peers=%s\n' "$(wg show wg0 latest-handshakes 2>/dev/null | wc -l)"
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

        expect "${probeName} on that path" "$(printf '%s' "$row" | cut -d'|' -f2)" "''${got_service:-NXDOMAIN}"
        expect "${deviceFqdn} on that path" "$(printf '%s' "$row" | cut -d'|' -f3)" "''${got_device:-NXDOMAIN}"
        expect "the blocklist answers NXDOMAIN" "yes" "''${blocked:-unknown}"
        expect "the tunnel has peers" "yes" "$([ "''${peers:-0}" -ge 1 ] && echo yes || echo no)"
      done

      printf '\n%s checks, %s failed\n' "$checks" "$fails"
      [ "$fails" -eq 0 ]
    '';
  };
in
audit
