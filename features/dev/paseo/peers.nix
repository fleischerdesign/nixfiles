# Peers and reconciliation for a Paseo daemon.
#
# Two deployment scopes need the same two answers: which other hosts are peers, and how a daemon
# converges its own registry onto that set. One file owns both, so the system daemon and the
# per-user daemon cannot drift apart - the difference between them is only who owns `$PASEO_HOME`.
{
  lib,
  pkgs,
  systems,
  hostName,
  package,
  stateDir,
  plugins,
  connectPeers,
  hub ? {
    enable = false;
  },
}:
let
  quote = lib.escapeShellArg;

  peers = lib.filterAttrs (
    name: host: name != hostName && (host.config.my.features.dev.paseo.daemon.enable or false)
  ) systems;

  # What each peer must look like in the daemon's own registry. A changed address does not replace
  # an old registration - `host add` appends - so the reconciliation compares against this map, and
  # the port comes from the peer's own configuration rather than from the local one.
  peerTargets = builtins.listToAttrs (
    map (
      peer:
      let
        peerCfg = systems.${peer}.config.my.features.dev.paseo.daemon;
        address = systems.${peer}.config.my.topology.hosts.${peer}.wireguardIpv4;
      in
      {
        name = peer;
        value = "tcp://${address}:${toString peerCfg.port}";
      }
    ) (lib.attrNames peers)
  );

  # Which registrations are stale: a saved host whose label is one of ours but whose target is no
  # longer the inventory's, plus exact duplicates left by a previous daemon identity. Kept as a
  # file so the jq program is not shell-quoted.
  staleHostsQuery = pkgs.writeText "paseo-stale-hosts.jq" ''
    def key: .label + "\u0000" + .targetDescription;
    . as $all
    | (
        $all[]
        | select((.label | in($want)) and ($want[.label] != .targetDescription))
        | .registrationId
      ),
      (
        $all
        | group_by(key)
        | map(sort_by(.status != "online") | .[1:])
        | add // []
        | .[].registrationId
      )
  '';

  # Peers, Hub enrollment and plugins are runtime state in `$PASEO_HOME`, because the daemon owns
  # those files. The unit reconciles them on every start instead of writing them.
  #
  # The script is a derivation rather than a systemd `script` block so shellcheck and `set -euo
  # pipefail` apply to it, and so a broken invocation fails the build instead of a host.
  configure = pkgs.writeShellApplication {
    name = "paseo-configure";
    runtimeInputs = [
      package
      pkgs.jq
    ];
    text = ''
      # The unit starts after the daemon, not when it is ready to answer. `daemon status` only
      # proves a PID exists; an RPC does, so the wait is a real request rather than a liveness
      # check - a daemon still loading plugins accepts the process but refuses work.
      ready=0
      for _ in {1..60}; do
        if paseo --home ${quote stateDir} host ls >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 2
      done
      if [ "$ready" -eq 0 ]; then
        echo "paseo: daemon did not answer within 120s" >&2
        exit 1
      fi

      # A saved host is keyed by its target and owned by the identity that created it, so neither a
      # changed address nor a restart replaces an entry: the registry accumulates. Reconcile it
      # instead of appending to it - drop what the inventory does not describe, collapse exact
      # duplicates, and add only the peers that are missing.
      registry="$(mktemp)"
      paseo --home ${quote stateDir} host ls --json > "$registry"
      jq -r --argjson want '${builtins.toJSON peerTargets}' -f ${staleHostsQuery} "$registry" \
        | while read -r stale; do
          timeout 60 paseo --home ${quote stateDir} host rm "$stale"
        done
      present="$(jq -r --argjson want '${builtins.toJSON peerTargets}' '
        [.[] | select(.label | in($want)) | select($want[.label] == .targetDescription) | .label]
        | unique
        | .[]
      ' "$registry")"
      rm -f "$registry"

      ${lib.concatMapStringsSep "\n" (peer: ''
        if ! printf '%s\n' "$present" | grep -qx ${quote peer}; then
          timeout 60 paseo --home ${quote stateDir} host add ${quote peerTargets.${peer}} --label ${quote peer}
        fi
      '') (if connectPeers then lib.attrNames peerTargets else [ ])}

      ${lib.optionalString hub.enable ''
        # The key travels in the environment, not in argv: a command line is world-readable in
        # the process list.
        PASEO_HUB_API_KEY="$(< ${quote hub.apiKeyPath})" \
          timeout 60 paseo --home ${quote stateDir} hub connect ${quote hub.origin} \
          ${lib.concatMapStringsSep " " (permission: "--permission ${quote permission}") hub.permissions}
      ''}

      ${lib.concatMapStringsSep "\n" (
        plugin: "timeout 180 paseo --home ${quote stateDir} plugin add ${quote plugin.source}"
      ) plugins}
    '';
  };
in
{
  inherit
    peers
    peerTargets
    configure
    ;
}
