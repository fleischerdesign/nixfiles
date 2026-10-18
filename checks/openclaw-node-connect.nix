# The enrollment helper stops the node unit for the duration of an enrollment, because a
# foreground node and the service share the state directory. That is only acceptable while the
# paths a caller may hit without intent - usage and flags - never reach the service: a --help
# probe from inside the node (an agent's exec host=node) used to stop the unit, kill the helper
# that would have started it again, and leave the node down, because an explicit stop suppresses
# Restart=always.
#
# The check runs the helper a host actually ships. The build sandbox has no user systemd, so every
# service call fails there - which is what turns the flag paths into measurements: a path that
# reached systemctl could not return the documented status 0 or 2.
{
  lib,
  pkgs,
  self,
  ...
}:
let
  host = self.nixosConfigurations.hom-wrk-01.config;
  user = host.home-manager.users.${host.my.user.primary};
  connect = lib.findFirst (
    package: (package.name or "") == "openclaw-node-connect"
  ) null user.home.packages;
in
assert connect != null;
pkgs.runCommandLocal "openclaw-node-connect-check" { } ''
  set -euo pipefail

  connect=${connect}/bin/openclaw-node-connect
  systemctl=${pkgs.systemd}/bin/systemctl

  # The measurements below read "the helper exited before it reached systemd". That only holds
  # while nothing answers on a user bus in the sandbox, so prove it instead of assuming it.
  if "$systemctl" --user show-environment >/dev/null 2>&1; then
    echo 'a user systemd answers in the build sandbox; the flag paths below measure nothing' >&2
    exit 1
  fi

  expect() {
    local expected=$1
    local status output
    shift
    set +e
    output=$("$connect" "$@" 2>&1)
    status=$?
    set -e
    if [ "$status" -ne "$expected" ]; then
      echo "exit $status, expected $expected: openclaw-node-connect $*" >&2
      echo "$output" >&2
      exit 1
    fi
    case "$output" in
      *"Usage: openclaw-node-connect"*) ;;
      *)
        echo "no usage text for: openclaw-node-connect $*" >&2
        echo "$output" >&2
        exit 1
        ;;
    esac
  }

  expect 0 --help
  expect 0 -h
  expect 2 --version
  expect 2 -x
  expect 2
  expect 2 oc-pair://example second-argument

  # A real target still reaches the enrollment, which cannot succeed without a user systemd.
  set +e
  "$connect" 'oc-pair://example' >/dev/null 2>&1
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo 'an enrollment reported success without a user systemd' >&2
    exit 1
  fi

  echo 'ok: usage and flag arguments leave the node unit untouched' > $out
''
