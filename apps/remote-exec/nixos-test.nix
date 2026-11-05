# Real SSH + systemd supervision acceptance for remote-exec.
#
# This is a NixOS VM test, not a fixture: a freshly declared executor account
# with its own host key, a real sshd and a real user systemd manager. It is
# deliberately not part of `nix flake check`; run it as
# `nix build .#remote-exec-ssh-test` when the transport or lifecycle changes.
{ pkgs }:
let
  keys =
    pkgs.runCommand "remote-exec-test-keys"
      {
        nativeBuildInputs = [ pkgs.openssh ];
      }
      ''
        mkdir -p $out
        ssh-keygen -q -t ed25519 -N "" -C host@test -f $out/host_ed25519
        ssh-keygen -q -t ed25519 -N "" -C remote-exec@test -f $out/client_ed25519
      '';
  package = pkgs.callPackage ./default.nix { };
in
pkgs.testers.nixosTest {
  name = "remote-exec-ssh";
  nodes.executor =
    { ... }:
    {
      imports = [ ../../features/services/remote-exec/nixos.nix ];
      services.openssh = {
        enable = true;
        hostKeys = [
          {
            type = "ed25519";
            path = "/etc/ssh/remote-exec-host-key";
          }
        ];
      };
      environment.etc."ssh/remote-exec-host-key".source = "${keys}/host_ed25519";
      environment.etc."ssh/remote-exec-host-key".mode = "0600";
      my.features.services.remote-exec = {
        enable = true;
        authorizedKeyFiles = [ "${keys}/client_ed25519.pub" ];
      };
    };
  nodes.gateway = {
    environment.systemPackages = [
      package
      pkgs.git
      pkgs.openssh
      pkgs.gnugrep
      pkgs.procps
    ];
  };

  testScript = ''
    import base64
    import json
    import shlex

    executor.start()
    gateway.start()
    executor.wait_for_unit("sshd.service")

    address = executor.succeed("hostname -I").split()[0]
    inventory = {
        "schemaVersion": 2,
        "hosts": {
            "executor": {
                "hostType": "server",
                "sshAddress": address,
                "architecture": "x86_64",
                "executor": {
                    "user": "remote-exec",
                    "root": "/var/lib/remote-exec",
                    "hostKey": open("${keys}/host_ed25519.pub").read().strip(),
                    "runtimePath": "/run/current-system/sw/bin",
                },
            }
        },
    }
    gateway.succeed("install -d -m 0755 /etc/openclaw")
    gateway.succeed(
        "echo %s | base64 -d > /etc/openclaw/remote-exec-inventory.json"
        % base64.b64encode(json.dumps(inventory).encode()).decode()
    )
    gateway.succeed("install -D -m 0600 ${keys}/client_ed25519 /root/.ssh/remote-exec")

    gateway.succeed(
        "mkdir -p /root/repo && cd /root/repo && "
        "git init -q && git config user.name test && git config user.email test@invalid && "
        "echo target/ > .gitignore && echo one > tracked.txt && "
        "git add -A && git commit -qm base"
    )

    common = (
        "--target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-1"
    )

    # 1. A normal build attempt: selected output only, ignored tree excluded,
    #    artifacts separately requested.
    producer = (
        "sh -c "
        + shlex.quote(
            'echo new > generated.rs; mkdir -p target; echo bin > target/binary; '
            'mkdir -p "$REMOTE_EXEC_ARTIFACTS"; echo artifact > "$REMOTE_EXEC_ARTIFACTS/a.txt"'
        )
    )
    gateway.succeed(
        "remote-exec run " + common + " --attempt-id ok-1 --repo /root/repo -- " + producer
        + " > /tmp/ok1.json"
    )
    gateway.succeed("grep -q 'stdoutPreview' /tmp/ok1.json")
    gateway.succeed(
        "remote-exec collect " + common + " --attempt-id ok-1 --out /root/out --delta --logs"
    )
    gateway.succeed("test -f /root/out/source/generated.rs")
    gateway.succeed("test ! -e /root/out/source/target")
    gateway.succeed("test -f /root/out/delta.json")
    gateway.succeed("test ! -e /root/out/artifacts")
    gateway.succeed(
        "remote-exec collect " + common + " --attempt-id ok-1 --out /root/out-artifacts --artifacts"
    )
    gateway.succeed("test -f /root/out-artifacts/artifacts/a.txt")

    # 2. At-most-one dispatch for the same attempt id.
    gateway.fail(
        "remote-exec run " + common + " --attempt-id ok-1 --repo /root/repo -- true"
    )

    # 3. Disconnect after dispatch: the unit keeps running, status reconciles it,
    #    and cancel stops the whole process tree.
    gateway.execute(
        "setsid remote-exec run " + common + " --attempt-id live-1 --timeout 300 "
        "--repo /root/repo -- sh -c 'sleep 300 & wait' > /tmp/live.log 2>&1 & echo $! > /tmp/live.pid"
    )
    gateway.wait_until_succeeds(
        "remote-exec status " + common + " --attempt-id live-1 | grep -q '\"phase\": \"running\"'",
        timeout=120,
    )
    # Kill the client's whole session: the CLI and its ssh child. The executor
    # unit is owned by the account's systemd manager and must keep running.
    gateway.succeed("kill -- -$(cat /tmp/live.pid) || true")
    gateway.wait_until_succeeds(
        "remote-exec status " + common + " --attempt-id live-1 | grep -q '\"phase\": \"running\"'",
        timeout=120,
    )
    gateway.succeed("remote-exec cancel " + common + " --attempt-id live-1")
    gateway.wait_until_succeeds(
        "remote-exec status " + common + " --attempt-id live-1 | grep -q '\"phase\": \"cancelled\"'",
        timeout=120,
    )
    executor.succeed("! pgrep -u remote-exec -f 'sleep 300'")

    # 4. A terminal attempt is never dispatched again.
    gateway.fail(
        "remote-exec run " + common + " --attempt-id live-1 --repo /root/repo -- true"
    )

    # 5. The same explicit attempt id in two runs must not share a unit.
    gateway.execute(
        "setsid remote-exec run --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-a --attempt-id shared --timeout 300 --repo /root/repo "
        "-- sh -c 'sleep 300 & wait' > /tmp/a.log 2>&1 &"
    )
    gateway.wait_until_succeeds(
        "remote-exec status --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-a --attempt-id shared | grep -q '\"phase\": \"running\"'",
        timeout=120,
    )
    gateway.execute(
        "setsid remote-exec run --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-b --attempt-id shared --timeout 300 --repo /root/repo "
        "-- sh -c 'sleep 300 & wait' > /tmp/b.log 2>&1 &"
    )
    gateway.wait_until_succeeds(
        "remote-exec status --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-b --attempt-id shared | grep -q '\"phase\": \"running\"'",
        timeout=120,
    )
    gateway.succeed(
        "remote-exec cancel --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-b --attempt-id shared"
    )
    gateway.wait_until_succeeds(
        "remote-exec status --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-b --attempt-id shared | grep -q '\"phase\": \"cancelled\"'",
        timeout=120,
    )
    # Cancelling B must not touch A's unit.
    gateway.succeed(
        "remote-exec status --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-a --attempt-id shared | grep -q '\"phase\": \"running\"'"
    )
    gateway.succeed(
        "remote-exec cancel --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-a --attempt-id shared"
    )
    gateway.wait_until_succeeds(
        "remote-exec status --target executor --identity /root/.ssh/remote-exec "
        "--repo-id test --run-id run-a --attempt-id shared | grep -q '\"phase\": \"cancelled\"'",
        timeout=120,
    )
    executor.succeed("! pgrep -u remote-exec -f 'sleep 300'")

    # 7. A reusable workspace keeps retained output, HOME and source mtimes
    #    across sequential attempts, and binds to the real repository.
    workspace = (
        "--target executor --identity /root/.ssh/remote-exec --repo-id test "
        "--workspace-id task --repo /root/repo"
    )
    warm = (
        "sh -c " + shlex.quote(
            'mkdir -p target; echo run >> target/count; echo home > "$HOME/state"; '
            'stat -c %Y tracked.txt > "$HOME/mtime.txt"; echo generated > generated.txt'
        )
    )
    gateway.succeed(
        "remote-exec run " + workspace + " --run-id warm-1 -- " + warm
        + " > /tmp/warm1.json"
    )
    gateway.succeed(
        "remote-exec run " + workspace + " --run-id warm-2 -- "
        + "sh -c " + shlex.quote(
            'test "$(cat target/count | wc -l)" = "2"; test "$(cat "$HOME/state")" = "home"; '
            'test "$(stat -c %Y tracked.txt)" = "$(cat "$HOME/mtime.txt")"'
        )
    )
    gateway.succeed(
        "remote-exec run " + workspace + " --run-id warm-3 -- "
        + "sh -c " + shlex.quote('test -f target/count && echo still-here > target/kept')
    )
    warm1_attempt = json.loads(
        gateway.succeed("cat /tmp/warm1.json")
    )["attemptId"]

    # One source change rebuilds against the existing work tree.
    gateway.succeed("echo changed > /root/repo/tracked.txt")
    gateway.succeed(
        "remote-exec run " + workspace + " --run-id warm-4 -- "
        + "sh -c " + shlex.quote('grep -q changed tracked.txt && echo rebuilt > generated.txt')
    )
    gateway.succeed("test -f /root/repo/tracked.txt")

    # An older attempt still collects its immutable snapshot after the
    # workspace has moved on.
    gateway.succeed(
        "remote-exec collect " + workspace + " --run-id warm-1 --attempt-id "
        + warm1_attempt + " --out /root/warm-out --delta"
    )
    gateway.succeed("grep -q 'generated' /root/warm-out/source/generated.txt")
    gateway.succeed("grep -q one /root/warm-out/source/tracked.txt")
    gateway.succeed("test -f /root/warm-out/delta.json")

    # 8. Exclusivity: a second attempt for the same workspace is refused while
    #    the first is live; cancel releases it through the lease.
    gateway.execute(
        "setsid remote-exec run " + workspace + " --run-id ws-live --timeout 300 "
        "-- sh -c 'sleep 300 & wait' > /tmp/ws-live.log 2>&1 & echo $! > /tmp/ws-live.pid"
    )
    gateway.wait_until_succeeds(
        "remote-exec workspace-status " + workspace + " | grep -q '\"phase\": \"running\"'",
        timeout=120,
    )
    # Killing the client session must not release the workspace lease or stop
    # the unit; a reconnect still observes the same attempt.
    gateway.succeed("kill -- -$(cat /tmp/ws-live.pid) || true")
    gateway.wait_until_succeeds(
        "remote-exec workspace-status " + workspace + " | grep -q '\"phase\": \"running\"'",
        timeout=120,
    )
    gateway.fail(
        "remote-exec run " + workspace + " --run-id ws-second -- true"
    )
    live_attempt = json.loads(
        gateway.succeed("remote-exec workspace-status " + workspace)
    )["lease"]["attemptId"]
    gateway.succeed(
        "remote-exec cancel " + workspace + " --run-id ws-live --attempt-id " + live_attempt
    )
    gateway.wait_until_succeeds(
        "remote-exec workspace-status " + workspace + " | grep -q '\"phase\": \"terminal\"'",
        timeout=120,
    )
    executor.succeed("! pgrep -u remote-exec -f 'sleep 300'")

    # 9. Explicit clean discards work and HOME, then a run succeeds.
    gateway.succeed(
        "remote-exec run " + workspace + " --run-id clean-1 --clean -- "
        + "sh -c " + shlex.quote('test ! -e target/count && test ! -e "$HOME/state"')
    )

    # 10. Prune is a dry run by default, keeps live attempts, and reset works.
    gateway.succeed(
        "remote-exec workspace-prune " + workspace + " --keep 1 --max-age-days 0 "
        "> /tmp/prune.json"
    )
    gateway.succeed("grep -q '\"dryRun\": true' /tmp/prune.json")
    gateway.succeed("remote-exec workspace-prune " + workspace + " --keep 1 --max-age-days 0 --apply")
    gateway.succeed("remote-exec workspace-status " + workspace)
    gateway.succeed("remote-exec workspace-reset " + workspace)
    gateway.succeed(
        "remote-exec run " + workspace + " --run-id after-reset -- true"
    )
  '';
}
