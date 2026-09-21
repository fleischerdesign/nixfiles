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
        # 600 is the metric NetworkManager gives a directly connected route, and it has to stay below the
        # wireguard interface's own metric (1000): the two routes have the same prefix, so the metric is
        # what decides between them.
        networking.networkmanager.dispatcherScripts = [
          {
            type = "basic";
            source = pkgs.writeShellScript "lan-preference" ''
              set -u

              HOME_DOOR=${homeDoor}
              LAN_ZONES="${lanZoneArgs}"
              CARRIED="${carriedArgs}"
              LAN_METRIC=600

              ip2int() { local a b c d; IFS=. read -r a b c d <<< "$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
              mask_int() { local len=''${1#*/}; echo $(( (0xffffffff << (32 - len)) & 0xffffffff )); }
              net_int() { local len=''${1#*/}; echo $(( $(ip2int "''${1%/*}") & $(mask_int "$len") )); }

              # The home zones this host currently has an address in, as `zone:cidr:gateway`.
              local_zones() {
                local entry address
                for address in $(ip -4 -o addr show | grep -oE '[0-9]+(\.[0-9]+){3}/[0-9]+'); do
                  case "$address" in 127.*) continue ;; esac
                  for entry in $LAN_ZONES; do
                    local cidr=''${entry#*:}; cidr=''${cidr%%:*}
                    local mask=''${cidr#*/}
                    if [ $(( $(ip2int "''${address%/*}") & $(mask_int "$mask") )) -eq "$(net_int "$cidr")" ]; then
                      echo "$entry"
                    fi
                  done
                done
              }

              at_home() {
                local entry
                for entry in $(local_zones); do
                  local cidr=''${entry#*:}; cidr=''${cidr%%:*}
                  for carried in $CARRIED; do
                    if [ "''${carried%%:*}" = "$cidr" ]; then continue 2; fi
                    ip route replace "''${carried%%:*}" via "''${entry##*:}" metric "$LAN_METRIC"
                  done
                done
              }

              away() {
                local carried
                resolvectl revert "$DEVICE" 2>/dev/null || true
                for carried in $CARRIED; do
                  ip route del "''${carried%%:*}" metric "$LAN_METRIC" 2>/dev/null || true
                done
              }

              case "''${ACTION:-}" in
                up|dhcp4-change|connectivity-change)
                  if [ -n "$(local_zones)" ]; then
                    # The rule of the link is more specific than the global one, so it wins without
                    # depending on which door answered last.
                    resolvectl dns "$DEVICE" "$HOME_DOOR" 2>/dev/null || true
                    resolvectl domain "$DEVICE" "~." 2>/dev/null || true
                    resolvectl flush-caches 2>/dev/null || true
                    at_home
                  else
                    away
                  fi
                  ;;
                down|pre-down)
                  away
                  ;;
              esac
            '';
          }
        ];
      };
}
