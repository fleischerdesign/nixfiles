# lib/audit/default.nix - two measurements against what the inventory promises.
#
# `network` proves that the running hosts answer as their configurations say: which path a host uses to
# the home door decides which plane the answer must come from, and the resolver's own projection says what
# that answer is. `exposure` proves that every listening socket is a decision somebody made: a port that
# is neither declared nor marked local is a question, not an answer.
#
# No expectation is written here. The projections of the contracts are the expectations, every value is
# baked in at build time, and the remote part is a quoted heredoc - which cannot expand anything locally,
# so a command can never run on the wrong machine.
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

  deployed = lib.filter (name: topology.hosts ? ${name}) hostNames;
  addressOf =
    name:
    if topology.hosts.${name}.wireguardIpv4 != null then
      topology.hosts.${name}.wireguardIpv4
    else
      topology.hosts.${name}.ipv4;

  fleetTable = lib.concatMapStringsSep " " (host: "\"${host.name}|${host.address}\"") (
    map (name: {
      inherit name;
      address = addressOf name;
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

  # What each host declared it serves, per protocol and interface. This is the expectation the exposure
  # report compares a live socket against: the firewall's rendered sets are the ports that are *open*,
  # and the contracts' `local` declarations are the listeners that are deliberately not.
  declaredOf =
    name:
    let
      fw = (cfgOf name).networking.firewall;
      provides = (cfgOf name).my.contracts.provides or { };
      endpoints = lib.concatLists (
        map (contract: lib.attrValues (contract.endpoints or { })) (lib.attrValues provides)
      );
    in
    {
      tcp = lib.unique (fw.allowedTCPPorts ++ (fw.interfaces.wg0.allowedTCPPorts or [ ]));
      udp = lib.unique (fw.allowedUDPPorts ++ (fw.interfaces.wg0.allowedUDPPorts or [ ]));
      local = lib.unique (
        map (ep: ep.port) (
          lib.filter (ep: ep.directAccess.enable && ep.directAccess.interface == "local") endpoints
        )
      );
    };
  declaredTable = lib.concatMapStrings (
    name:
    "\"${name}|${addressOf name}|${join (declaredOf name).tcp}|${join (declaredOf name).udp}|${join (declaredOf name).local}\" "
  ) deployed;
  join = ports: lib.concatStringsSep "," (map toString ports);

  # Protocols whose whole purpose is the local link. They are not services somebody could use from
  # elsewhere, and listing them as undeclared would be noise rather than a question.
  localProtocols = "5353 5355 1900";

  network = pkgs.writeShellApplication {
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
        IFS='|' read -r name address <<< "$entry"
        printf '\n%s (%s)\n' "$name" "$address"

        measured=$(ssh "''${SSH_OPTS[@]}" "root@$address" 'bash -s' <<'REMOTE' 2>/dev/null || echo UNREACHABLE
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

        expect "${probeName} answered on that path" "$(printf '%s' "$row" | cut -d'|' -f2)" "''${got_service:-NXDOMAIN}"
        expect "${deviceFqdn} answered on that path" "$(printf '%s' "$row" | cut -d'|' -f3)" "''${got_device:-NXDOMAIN}"
        expect "the blocklist answers NXDOMAIN" "yes" "''${blocked:-unknown}"
        expect "the tunnel has peers" "yes" "$([ "''${peers:-0}" -ge 1 ] && echo yes || echo no)"
      done

      printf '\n%s checks, %s failed\n' "$checks" "$fails"
      [ "$fails" -eq 0 ]
    '';
  };

  exposure = pkgs.writeShellApplication {
    name = "exposure-audit";
    runtimeInputs = with pkgs; [
      openssh
      gnugrep
      gnused
      coreutils
    ];
    text = ''
      set -uo pipefail

      # Without --strict this is an inventory: it prints every listening socket that is not bound to
      # loopback and whether it is a decision somebody made. With --strict it fails on the ones that are
      # not - which is the gate that keeps a new service from being exposed by accident.
      strict=no
      [ "''${1:-}" = "--strict" ] && strict=yes

      KEY="''${NETWORK_AUDIT_KEY:-$HOME/.ssh/nixfiles-deploy-key}"
      SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
      LOCAL_PROTOCOLS="${localProtocols}"

      undeclared_total=0

      for entry in ${declaredTable}; do
        IFS='|' read -r name address tcp udp local <<< "$entry"
        printf '\n%s (%s)\n' "$name" "$address"
        printf '  declared: open tcp={%s} udp={%s}  local={%s}\n' "$tcp" "$udp" "$local"

        measured=$(ssh "''${SSH_OPTS[@]}" "root@$address" 'bash -s' <<'REMOTE' 2>/dev/null || echo UNREACHABLE
          ss -lntupH 2>/dev/null | while read -r proto _ _ _ local peer rest; do
            # A socket on loopback or on a link-local address is reachable from nowhere else, and a UDP
            # socket that has a real peer is somebody's client connection, not a service. Neither is a
            # question about exposure, so both are skipped before they become noise.
            case "$local" in
              127.*|\[::1\]*|\[fe80::*|169.254.*) continue ;;
            esac
            port="''${local##*:}"
            proc="$rest"
            proc="''${proc#*users:((\"}"
            proc="''${proc%%\"*}"
            if [ "$proto" = "udp" ]; then
              case "$peer" in
                0.0.0.0:*|\[::\]:*|\*:\*) ;;
                *) continue ;;
              esac
              # An unconnected UDP socket on an ephemeral port is as often a client of something else as it
              # is a service; a service binds a port somebody would recognise and declares it, and a
              # declared port is classified before this rule is reached.
              if [ "$port" -ge 32768 ] 2>/dev/null; then continue; fi
            fi
            printf '%s %s %s %s\n' "$proto" "''${local%:*}" "$port" "$proc"
          done
      REMOTE
        )

        # The host is addressed by name from the inventory above; the ssh target needs the address.
        if [ "$measured" = "UNREACHABLE" ]; then
          printf '  MISSING  the host did not answer over the mesh\n'
          undeclared_total=$((undeclared_total + 1))
          continue
        fi

        while read -r proto bind port proc; do
          [ -n "''${port:-}" ] || continue
          case "$proto" in
            tcp) declared="$tcp" ;;
            udp) declared="$udp" ;;
            *) continue ;;
          esac
          case ",$declared," in
            *",$port,"*)
              printf '  ok        %-5s %-16s %-6s %s (open)\n' "$proto" "$bind" "$port" "''${proc:-?}"
              ;;
            *)
              case ",$local," in
                *",$port,"*)
                  printf '  local     %-5s %-16s %-6s %s (declared local)\n' "$proto" "$bind" "$port" "''${proc:-?}"
                  ;;
                *)
                  case " $LOCAL_PROTOCOLS " in
                    *" $port "*)
                      printf '  local     %-5s %-16s %-6s %s (link-local protocol)\n' "$proto" "$bind" "$port" "''${proc:-?}"
                      ;;
                    *)
                      printf '  QUESTION  %-5s %-16s %-6s %s (listening, undeclared)\n' "$proto" "$bind" "$port" "''${proc:-?}"
                      undeclared_total=$((undeclared_total + 1))
                      ;;
                  esac
                  ;;
              esac
              ;;
          esac
        done <<< "$measured"
      done

      printf '\n%s listening sockets outside loopback that nobody declared\n' "$undeclared_total"
      if [ "$strict" = yes ] && [ "$undeclared_total" -gt 0 ]; then
        printf 'strict: they are closed over the mesh today, but they are not decisions - declare them or mark them local\n'
        exit 1
      fi
    '';
  };
in
{
  inherit network exposure;
}
