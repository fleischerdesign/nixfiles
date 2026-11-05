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
    )
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
  '';
}
