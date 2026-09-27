# apps/exposure-audit/default.nix - is every listening socket a decision somebody made?
#
# A port that is neither declared nor marked local is a question, not an answer.
#
# What each host declared is read from the declarations, not from the rendered firewall, because the
# declarations are what the firewall is rendered *from*: an endpoint that declares a port has it, and
# one that does not, has not.
{
  pkgs,
  lib,
  hostNames,
  self,
}:
let
  fleet = import ../lib/fleet.nix { inherit lib hostNames self; };
  inherit (fleet) cfgOf deployed addressOf;

  # What each host declared it serves, per protocol and interface. This is the expectation the exposure
  # report compares a live socket against.
  declaredOf =
    name:
    let
      fw = (cfgOf name).networking.firewall;
      provides = (cfgOf name).my.contracts.provides or { };
      endpoints = lib.concatLists (
        map (
          contract: lib.mapAttrsToList (epName: ep: ep // { inherit epName; }) (contract.endpoints or { })
        ) (lib.attrValues provides)
      );
      # A named publication is what puts a listener behind the ingress on the mesh interface; the
      # firewall is rendered from the same predicate, so the audit reads it from the same place.
      proxied = lib.concatLists (
        map (
          contract:
          lib.mapAttrsToList (_: pub: pub.endpoint) (
            lib.filterAttrs (_: pub: pub.canonicalDomain != null) (contract.publications or { })
          )
        ) (lib.attrValues provides)
      );
      meshInterface = (cfgOf name).my.features.system.networking.wireguard.interfaceName;
      withProto =
        proto:
        lib.unique (
          map (ep: ep.port) (
            lib.filter (
              ep:
              # The same predicate the firewall is rendered from: a port is a decision when the endpoint
              # declared direct access, or when a named publication makes an ingress reach it over the mesh.
              (ep.directAccess.enable || builtins.elem ep.epName proxied)
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
        fw.allowedTCPPorts ++ (fw.interfaces.${meshInterface}.allowedTCPPorts or [ ]) ++ withProto "tcp"
      );
      udp = lib.unique (
        fw.allowedUDPPorts ++ (fw.interfaces.${meshInterface}.allowedUDPPorts or [ ]) ++ withProto "udp"
      );
      local = lib.unique (
        map (ep: ep.port) (
          lib.filter (ep: ep.directAccess.enable && ep.directAccess.interface == "local") endpoints
        )
      );
    };
  join = ports: lib.concatStringsSep "," (map toString ports);
  declaredTable = lib.concatMapStrings (
    name:
    "\"${name}|${addressOf name}|${join (declaredOf name).tcp}|${join (declaredOf name).udp}|${join (declaredOf name).local}\" "
  ) deployed;

  # Protocols whose whole purpose is the local link. They are not services somebody could use from
  # elsewhere, and listing them as undeclared would be noise rather than a question.
  localProtocols = "5353 5355 1900";
in
pkgs.writeShellApplication {
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
}
