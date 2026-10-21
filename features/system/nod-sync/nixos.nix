# features/system/nod-sync/nixos.nix
# Pull-based GitOps reconciliation: one host tracks a branch and deploys the
# fleet it declares. The daemon owns the checkout, the state and the lock; the
# repository stays the source of truth and nothing is deployed that was not
# committed (ADR-028).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.system.nod-sync;
  nod = inputs.nod.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # A fresh host has no checkout. The daemon fetches on its own afterwards;
  # this only makes the first start work without an operator step.
  checkout = pkgs.writeShellScript "nod-sync-checkout" ''
    set -euo pipefail
    root=${lib.escapeShellArg cfg.flakePath}
    if [ -e "$root" ] && [ ! -d "$root/.git" ]; then
      echo "nod-sync: $root exists but is not a git checkout; refusing to guess" >&2
      exit 1
    fi
    if [ ! -d "$root/.git" ]; then
      mkdir -p "$(dirname "$root")"
      ${pkgs.git}/bin/git clone \
        --branch ${lib.escapeShellArg cfg.branch} \
        --single-branch \
        ${lib.escapeShellArg cfg.repository} \
        "$root"
    fi
    chown -R root:root "$root"
  '';

  targetFlags =
    if cfg.targets == [ ] then
      "--all"
    else
      lib.concatMapStringsSep " " (t: "--target ${lib.escapeShellArg t}") cfg.targets;

  # The public entry point is the last thing a rollout may disturb; everything
  # else can be replaced while it keeps serving.
  lastHostFlags = lib.concatMapStringsSep " " (
    h: "--last-host ${lib.escapeShellArg h}"
  ) cfg.lastHosts;

  command = lib.concatStringsSep " " [
    "${nod}/bin/nod"
    "daemon"
    "--flake ${lib.escapeShellArg cfg.flakePath}"
    "--remote origin"
    "--branch ${lib.escapeShellArg cfg.branch}"
    "--interval ${toString cfg.interval}"
    "--gate-interval ${toString cfg.gateInterval}"
    "--offline-backoff ${toString cfg.offlineBackoff}"
    "--offline-backoff-max ${toString cfg.offlineBackoffMax}"
    "--gone-after ${toString cfg.goneAfter}"
    "--jitter ${toString cfg.jitter}"
    "--strategy ${cfg.strategy}"
    "--concurrency ${toString cfg.concurrency}"
    targetFlags
    lastHostFlags
  ];
in
{
  options.my.features.system.nod-sync = {
    enable = lib.mkEnableOption "pull-based GitOps reconciliation with nod";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/fleischerdesign/nixfiles.git";
      description = "Repository the daemon tracks. Must be readable without credentials.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch the daemon integrates.";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nod/nixfiles";
      description = "Root-owned checkout the daemon reconciles.";
    };

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Target specifiers; empty deploys the whole discovered fleet.";
    };

    interval = lib.mkOption {
      type = lib.types.ints.between 15 3600;
      default = 60;
      description = "Reconciliation interval in seconds (ADR-028 minimum is 15).";
    };

    gateInterval = lib.mkOption {
      type = lib.types.ints.between 0 3600;
      default = 15;
      description = ''
        Interval in seconds between remote-head checks that may start a sweep
        early. The sweep keeps its own cadence regardless: host drift happens
        without a push. Set to 0 to disable the gate, which is what a
        repository on a local path requires.
      '';
    };

    offlineBackoff = lib.mkOption {
      type = lib.types.ints.between 1 3600;
      default = 60;
      description = ''
        First retry delay in seconds for a host that does not answer. The delay
        doubles per failed probe, so an absent host costs no probe instead of
        one per interval.
      '';
    };

    offlineBackoffMax = lib.mkOption {
      type = lib.types.ints.between 1 86400;
      default = 1800;
      description = "Ceiling in seconds for the offline retry delay.";
    };

    goneAfter = lib.mkOption {
      type = lib.types.ints.between 0 2592000;
      default = 86400;
      description = ''
        Seconds offline after which `nod sync-status` labels a host as gone
        rather than unreachable. A label, never a removal: the inventory stays
        the truth. Set to 0 to disable the distinction.
      '';
    };

    jitter = lib.mkOption {
      type = lib.types.ints.between 0 50;
      default = 10;
      description = "Random spread applied to the interval, in percent.";
    };

    strategy = lib.mkOption {
      type = lib.types.enum [
        "all"
        "canary"
        "batch"
      ];
      default = "canary";
      description = "Rollout strategy; canary warms one host before the rest.";
    };

    concurrency = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Maximum in-flight hosts.";
    };

    lastHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hosts deployed after every other target (public ingress, control plane).";
    };
  };

  config = lib.mkIf cfg.enable {
    # The reconciler deploys remote hosts as root over SSH, so root needs the
    # fleet deploy key and no interactive prompt. The key is the fleet's
    # existing deploy identity, not a second one.
    #
    # It is installed at the default identity path on purpose: `nix copy --to
    # ssh://` uses Nix's own SSH client (libssh2), which never reads
    # /etc/ssh/ssh_config. A Match rule alone therefore authenticates the
    # interactive `ssh` calls but not the closure transfer.
    sops.secrets."infra/deploy_key" = {
      # The fleet deploy key is a separate SOPS document, deliberately not
      # encrypted to the CI identity; sops-nix needs the file named explicitly.
      sopsFile = ../../../secrets/deploy-key.yaml;
      path = "/root/.ssh/id_ed25519";
      mode = "0400";
    };

    # libssh2 also verifies host keys against the user's known_hosts, not the
    # system-wide file. Root's is a link to the projected trust anchors.
    #
    # The fleet metadata declares `identityFile = ~/.ssh/nixfiles-deploy-key`,
    # and nod passes it verbatim as `-i`. Root's home must therefore contain
    # that path as well, or every call logs a warning about a missing key.
    systemd.tmpfiles.rules = [
      "d /root/.ssh 0700 root root -"
      "L+ /root/.ssh/known_hosts - - - - /etc/ssh/ssh_known_hosts"
      "L+ /root/.ssh/nixfiles-deploy-key - - - - /root/.ssh/id_ed25519"
    ];

    programs.ssh.extraConfig = ''
      Match host 10.10.100.* user root
          IdentityFile ${config.sops.secrets."infra/deploy_key".path}
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
    '';

    # The daemon writes the history, operators read it, and both must mean the
    # same file. A unit-only variable would leave every interactive `nod audit`
    # reading its own home again - the exact confusion the shared path removes.
    environment.variables.NOD_AUDIT_PATH = "/var/lib/nod/history.json";

    systemd.services.nod-sync = {
      description = "nod GitOps reconciler (${cfg.branch})";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "wireguard-wg0.service"
      ];
      # The daemon shells out to git, nix and ssh; the unit's PATH is the
      # contract, not the host profile.
      path = [
        pkgs.git
        pkgs.nix
        pkgs.openssh
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = checkout;
        ExecStart = command;
        StateDirectory = "nod";
        # The history must outlive the daemon and stay readable for whoever asks
        # `nod audit`. Left to `$HOME`, the service account's copy would be
        # invisible to every operator; the path is shared instead. The store
        # itself sets the file mode, so the directory only needs to be traversable.
        Environment = "NOD_AUDIT_PATH=/var/lib/nod/history.json";
        StateDirectoryMode = "0755";
        # A refusal or a failed cycle is reported, not fatal; only a broken
        # invocation exits, and then systemd must not spin.
        Restart = "on-failure";
        RestartSec = 30;
        # Activating this host stops this unit, because the unit itself is
        # part of the generation being switched to. With the default kill mode
        # systemd would also kill the `switch-to-configuration` child that is
        # performing the activation - the daemon shot itself in the foot and
        # left the host on the old generation. `process` limits the stop signal
        # to the daemon, so the switch completes and starts the new unit.
        KillMode = "process";
        UMask = "0077";
        PrivateTmp = true;
        # No ProtectSystem: a local activation writes /etc, /run and the Nix
        # store, so sandboxing the filesystem here would only produce a
        # misleading hardening claim. The unit is root by design; the control
        # is what reaches it (review before merge), not a namespace.
      };
    };
  };
}
