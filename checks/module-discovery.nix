# checks/module-discovery.nix - the import contract, written down and checked.
#
# The discovery of NixOS modules is a build input, so it has to behave: only a regular `nixos.nix`
# file is a module, a helper that shares no name with the marker is not, the former `default.nix`
# marker is gone, and a malformed marker fails loudly instead of being skipped quietly. The fixture
# trees in `checks/fixtures/discovery` encode those decisions, and this check reads them the same way
# the system builder does - through `lib/discovery.nix`, not a second implementation of it.
{
  pkgs,
  lib,
}:
let
  loader = import ../lib/discovery.nix { inherit lib; };
  fixtures = ./fixtures/discovery;

  found = map (path: lib.removePrefix "${toString fixtures}/" path) (
    map toString (loader.findModules fixtures)
  );

  # What must be found: the plain module, the nested parent and child, and the feature that carries
  # a helper (the helper's files must not appear). The helper file in the plain directory must not
  # appear either - it is not named `nixos.nix`, so it is not a module. `old-style/default.nix` uses
  # the former marker and must not be discovered either: its absence is the evidence the rename
  # happened once and everywhere.
  expectedFound = [
    "helpers/nixos.nix"
    "nested/child/nixos.nix"
    "nested/nixos.nix"
    "plain/nixos.nix"
  ];

  # A directory named like the marker is a mistake, and the loader throws for it. The malformed
  # fixture lives apart so its throw does not break this evaluation; `tryEval` observes the throw
  # instead. `deepSeq` matters: without it the list stays unevaluated and the throw never fires.
  malformed = builtins.tryEval (
    builtins.deepSeq (loader.findModules ./fixtures/discovery-malformed) true
  );
in
pkgs.runCommandLocal "module-discovery-check"
  {
    nativeBuildInputs = [ pkgs.jq ];
    foundJson = builtins.toJSON found;
    expectedJson = builtins.toJSON expectedFound;
  }
  ''
    fail=0
    unexpected=$(jq -r '.[]' <<< "$foundJson" | grep -vxFf <(jq -r '.[]' <<< "$expectedJson") || true)
    missing=$(jq -r '.[]' <<< "$expectedJson" | grep -vxFf <(jq -r '.[]' <<< "$foundJson") || true)
    leftovers=$(jq -r '.[]' <<< "$foundJson" | grep '/default\.nix$' || true)
    if [ -n "$unexpected" ]; then
      echo "module discovery found files it must not:" >&2
      echo "$unexpected" >&2
      fail=1
    fi
    if [ -n "$missing" ]; then
      echo "module discovery did not find:" >&2
      echo "$missing" >&2
      fail=1
    fi
    if [ -n "$leftovers" ]; then
      echo "the former default.nix marker is still discovered:" >&2
      echo "$leftovers" >&2
      fail=1
    fi
    ${
      if !malformed.success then
        "# the loader threw on the malformed marker, as it must"
      else
        ''
          echo "the loader accepted a directory named nixos.nix instead of throwing" >&2
          exit 1
        ''
    }
    [ "$fail" -eq 0 ] || exit 1
    echo "ok: module discovery found exactly the intended modules" > $out
  ''
