# features/system/networking/migration-guard/default.nix
#
# Migration connectivity guard.
#
# A subnet migration changes the host's addressing and its default route. If that goes wrong the
# host is unreachable - and on a host without out-of-band console access the only recovery path
# is a local one. This unit therefore runs once, shortly after the generation is activated, and
# rolls the host back to the previous generation if the network did not come back.
#
# It exists exactly while `my.topology.hosts.<self>.migration` declares transitional addressing:
# the teardown (DEPLOYMENT §14) empties that block, which removes this guard automatically.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  topology = config.my.features.system.networking.topology;
  hostTopology = topology.hosts.${config.networking.hostName} or null;

  migration =
    if hostTopology == null then
      {
        addresses = [ ];
        gateway = null;
      }
    else
      hostTopology.migration;

  # Both gates are acceptable: right after the cutover the old one may be gone while the new one
  # is not yet in charge, and vice versa.
  gateways = lib.filter (g: g != null) [
    migration.gateway
    (if hostTopology == null then null else hostTopology.gateway)
  ];

  # No separate switch: the guard exists exactly while the host declares transitional
  # addressing. There is nothing to enable and nothing to forget.
  active = lib.length migration.addresses > 0;
in
{
  config = lib.mkIf active {
    systemd.services.migration-connectivity-guard = {
      description = "Roll back to the previous generation if the network did not survive";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u
        log() { echo "[migration-guard] $*"; }

        # The gateways that may legitimately answer; either one is fine.
        gates="${lib.concatStringsSep " " gateways}"

        check() {
          # A default route alone is not enough: it may point at a gateway that is no longer there.
          ip -4 route show default | grep -q . || return 1
          for g in $gates; do
            ping -c1 -W2 "$g" >/dev/null 2>&1 && return 0
          done
          # Last resort: the outside world.
          ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && return 0
          return 1
        }

        # Give the interfaces and the uplink time to settle, then retry for three minutes.
        sleep 30
        for _ in $(seq 1 18); do
          if check; then
            log "connectivity verified, nothing to do"
            exit 0
          fi
          sleep 10
        done

        log "ERROR: no default route or reachable gateway after activation"
        log "rolling back to the previous generation to restore access"
        if nixos-rebuild switch --rollback; then
          log "rollback applied"
        else
          log "rollback FAILED - manual intervention required"
        fi
      '';
    };

    systemd.timers.migration-connectivity-guard = {
      description = "Arm the migration connectivity guard once per generation activation";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Fires once, two minutes after this unit is started - which is either boot or the
        # activation of this generation. It never repeats, so a later, deliberate outage
        # (moving the router, handing DHCP over) cannot trigger a rollback.
        OnActiveSec = "2min";
        AccuracySec = "15s";
      };
    };
  };
}
