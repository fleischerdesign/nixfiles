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

  command = lib.concatStringsSep " " [
    "${nod}/bin/nod"
    "daemon"
    "--flake ${lib.escapeShellArg cfg.flakePath}"
    "--remote origin"
    "--branch ${lib.escapeShellArg cfg.branch}"
    "--interval ${toString cfg.interval}"
    "--jitter ${toString cfg.jitter}"
    "--strategy ${cfg.strategy}"
    "--concurrency ${toString cfg.concurrency}"
    targetFlags
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
  };

  config = lib.mkIf cfg.enable {
    # The reconciler deploys remote hosts as root over SSH, so root needs the
    # fleet deploy key and no interactive prompt. The key is the fleet's
    # existing deploy identity, not a second one; the SSH rule is scoped to
    # root so no other account silently picks it up.
    sops.secrets."infra/deploy_key" = {
      # The fleet deploy key is a separate SOPS document, deliberately not
      # encrypted to the CI identity; sops-nix needs the file named explicitly.
      sopsFile = ../../../secrets/deploy-key.yaml;
    };
    programs.ssh.extraConfig = ''
      Match user root address 10.10.100.0/24
          IdentityFile ${config.sops.secrets."infra/deploy_key".path}
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
    '';

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
        # A refusal or a failed cycle is reported, not fatal; only a broken
        # invocation exits, and then systemd must not spin.
        Restart = "on-failure";
        RestartSec = 30;
        KillMode = "mixed";
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
