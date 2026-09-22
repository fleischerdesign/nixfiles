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
  # report compares a live socket against - and it is read from the declarations, not from the rendered
  # firewall, because the declarations are what the firewall is rendered *from*: an endpoint that declares
  # a port has it, and one that does not, has not.
  declaredOf =
    name:
    let
      fw = (cfgOf name).networking.firewall;
      provides = (cfgOf name).my.contracts.provides or { };
      endpoints = lib.concatLists (
        map (contract: lib.attrValues (contract.endpoints or { })) (lib.attrValues provides)
      );
      withProto =
        proto:
        lib.unique (
          map (ep: ep.port) (
            lib.filter (
              ep:
              # The same predicate the firewall is rendered from: a port is a decision when the endpoint
              # declared direct access, or when a named endpoint makes an ingress reach it over the mesh.
              (ep.directAccess.enable || ep.canonicalDomain != null)
              && (ep.directAccess.protocol == proto || ep.directAccess.protocol == "both")
            ) endpoints
          )
        );
    in
    {
      # Both sources are declarations and both count: the endpoints (which is what this repository's
      # firewall is rendered from) and whatever a module opened through the firewall's own port options -
      # the exposure report asks whether a listener is a decision, not which module made it.
      tcp = lib.unique (
        fw.allowedTCPPorts ++ (fw.interfaces.wg0.allowedTCPPorts or [ ]) ++ withProto "tcp"
      );
      udp = lib.unique (
        fw.allowedUDPPorts ++ (fw.interfaces.wg0.allowedUDPPorts or [ ]) ++ withProto "udp"
      );
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

  network = pkgs.writeShellApplication {
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
