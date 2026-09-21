# features/system/networking/lan-preference/default.nix - while this host is in the home LAN, the home
# LAN is the path: for names and for addresses.
#
# Two measured facts make this necessary rather than nice:
#
#   * systemd-resolved keeps answering through the door that answered last, so a node that was away
#     keeps asking the mesh door while it sits at home - and gets overlay addresses for LAN services;
#   * a carried zone is a `/24` in the tunnel, and a `/24` beats the node's own default route by
#     longest prefix. A route metric only orders equal prefixes, so the tunnel's metric cannot save
#     this case either.
#
# What "at home" means is already in the inventory: the host holds an address in one of the home zones,
# and then it reaches every other home zone through that zone's gateway - exactly like every other home
# address. So this is derived, not configured: the link that holds such an address gets the home door as
# its own resolver with a default routing domain (more specific than the global list, therefore
# preferred), and every carried zone the host is not itself inside gets a route of the same prefix
# through its zone gateway at a lower metric than the tunnel's. Both are withdrawn when the address is
# gone, so the away behaviour is untouched.
#
# The work belongs to the dispatcher because NetworkManager is what learns that the host joined a
# network, and "which network am I on" is the question this answers.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.system.networking.lan-preference;
  topology = config.my.topology;
  ownHost = topology.hosts.${config.networking.hostName} or null;

  lanRouter = topology.hosts.${topology.lanRouter} or { };
  homeDoor = lanRouter.ipv4 or null;

  # `zone:cidr:gateway` for the zones that mean "home", and `cidr:gateway` for the zones the mesh
  # carries. Both are read from the topology, so the script holds no address of its own.
  lanZoneArgs = lib.concatMapStrings (
    zone: " ${zone}:${topology.subnets.${zone}.cidr}:${topology.subnets.${zone}.gateway}"
  ) topology.lanZones;
  carriedArgs = lib.concatMapStrings (
    zone: " ${topology.subnets.${zone}.cidr}:${topology.subnets.${zone}.gateway}"
  ) topology.announcedZones;

  # Only a host whose own zone is a home zone can find itself at home: a cloud host never does, and a
  # roaming node is declared in a home zone. Everything else is decided at runtime by the address the
  # host actually holds.
  canBeAtHome = ownHost != null && builtins.elem ownHost.zone topology.lanZones;
in
{
  options.my.features.system.networking.lan-preference = {
    enable = lib.mkEnableOption "Using the home LAN as the path while the host is inside it";
  };

  config =
    lib.mkIf (cfg.enable && canBeAtHome && homeDoor != null && topology.announcedZones != [ ])
      {
        # A dispatch fires on link events, and a deploy produces none: measured, the notebook sat with
        # the door of the *old* script (`~.` on the link) after two deploys and answered the same name
        # from two different planes depending on which server resolved it first. So the same script runs
        # once at activation as well - one script, two triggers, no second copy of the rule.
        systemd.services.lan-preference = {
          description = "Apply the at-home preference at activation";
          wantedBy = [ "multi-user.target" ];
          wants = [ "NetworkManager.service" ];
          after = [ "NetworkManager.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            for path in /sys/class/net/*; do
              device=$(basename "$path")
              [ "$device" = "lo" ] || ACTION=up DEVICE="$device" ${(lib.head config.networking.networkmanager.dispatcherScripts).source} || true
            done
          '';
        };

        # 600 is the metric NetworkManager gives a directly connected route, and it has to stay below the
        # wireguard interface's own metric (1000): the two routes have the same prefix, so the metric is
        # what decides between them. Every binary is named by its store path, because a dispatcher runs
        # in an environment with a bare PATH - measured: `ip: command not found`, which would leave the
        # script silently doing nothing, the one failure mode that looks exactly like success.
        networking.networkmanager.dispatcherScripts = [
          {
            type = "basic";
            source = pkgs.writeShellScript "lan-preference" ''
              set -u

              IP=${pkgs.iproute2}/bin/ip
              RESOLVECTL=${pkgs.systemd}/bin/resolvectl

              HOME_DOOR=${homeDoor}
              INTERNAL_DOMAIN=${topology.domain}
              LAN_ZONES="${lanZoneArgs}"
              CARRIED="${carriedArgs}"
              LAN_METRIC=600
              # The device the override was last given to, so it can be taken back from *that* device:
              # a link event for a different link must not withdraw the home rule, and one for the tunnel
              # must not leave the override behind on it.
              STATE=/run/lan-preference.device

              ip2int() { local a b c d; IFS=. read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
              mask_int() { local len=''${1#*/}; echo $(( (0xffffffff << (32 - len)) & 0xffffffff )); }
              net_int() { local len=''${1#*/}; echo $(( $(ip2int "''${1%/*}") & $(mask_int "$len") )); }

              # The home zones this host currently has an address in, as `device:zone:cidr:gateway`. The
              # device is read off the address, never off the event: NetworkManager reports the tunnel
              # coming up while the LAN address is already there, and the rule is about the link that
              # *holds* the address. Measured with the event's device: the notebook got the home door on
              # wg0, asked it with its overlay source address and timed out - while the same question over
              # the LAN address was answered.
              home_addresses() {
                local device address entry cidr rest
                "$IP" -4 -o addr show scope global | while read -r _ device _ address rest; do
                  case "$address" in */*) ;; *) continue ;; esac
                  for entry in $LAN_ZONES; do
                    cidr=''${entry#*:}; cidr=''${cidr%%:*}
                    if [ $(( $(ip2int "''${address%/*}") & $(mask_int "''${cidr#*/}") )) -eq "$(net_int "$cidr")" ]; then
                      echo "$device:$entry"
                    fi
                  done
                done
              }

              home_device() {
                local entry
                for entry in $(home_addresses); do echo "''${entry%%:*}"; return; done
              }

              local_zones() {
                local entry
                for entry in $(home_addresses); do echo "''${entry#*:}"; done
              }

              # One question, asked on every link event: does this host hold an address in a home zone,
              # and on which link? The tunnel coming up, the LAN coming back and an activation all reach
              # the same answer, and the override is taken back from the device it was given to - so a
              # link event with nothing to do with the home LAN cannot disturb it in either direction.
              reconcile() {
                local device previous entry cidr carried
                device=$(home_device)
                previous=
                [ -f "$STATE" ] && read -r previous < "$STATE"

                if [ -n "$previous" ] && [ "$previous" != "$device" ]; then
                  "$RESOLVECTL" revert "$previous" 2>/dev/null || true
                  "$RESOLVECTL" reset-server-features 2>/dev/null || true
                  : > "$STATE"
                fi

                if [ -z "$device" ]; then
                  for carried in $CARRIED; do
                    "$IP" route del "''${carried%%:*}" metric "$LAN_METRIC" 2>/dev/null || true
                  done
                  return
                fi

                # The link's rule is the internal domain, not everything: a more specific rule than
                # the global one, so it wins. A second `~.` does not - measured: the global scope
                # kept the door that had answered last, and the notebook at home still received
                # overlay addresses. Names outside the domain keep following the global list, where
                # either door answers alike, which is what makes the sticky server harmless.
                "$RESOLVECTL" dns "$device" "$HOME_DOOR" 2>/dev/null || true
                "$RESOLVECTL" domain "$device" "~$INTERNAL_DOMAIN" 2>/dev/null || true
                # The global scope keeps the door that answered last; resetting the server features makes
                # it start from the top of its list again, which is where the home door sits.
                "$RESOLVECTL" reset-server-features 2>/dev/null || true
                "$RESOLVECTL" flush-caches 2>/dev/null || true
                echo "$device" > "$STATE"

                for entry in $(local_zones); do
                  cidr=''${entry#*:}; cidr=''${cidr%%:*}
                  for carried in $CARRIED; do
                    if [ "''${carried%%:*}" = "$cidr" ]; then continue 2; fi
                    "$IP" route replace "''${carried%%:*}" via "''${entry##*:}" metric "$LAN_METRIC"
                  done
                done
              }

              case "''${ACTION:-}" in
                up|dhcp4-change|connectivity-change|down|pre-down) reconcile ;;
              esac
            '';
          }
        ];
      };
}
