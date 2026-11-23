# A failover patch that misses one boundary silently leaves OpenCode Go limits unhandled.
{ pkgs, ... }:
let
  file =
    path:
    builtins.path {
      inherit path;
      name = baseNameOf path;
    };
in
pkgs.runCommand "openchamber-failover" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python ${file ./fixtures/openchamber/failover-test.py} \
    ${file ../features/dev/openchamber/patch-limit-failover.py} \
    ${file ./fixtures/openchamber/failover}
  touch "$out"
''
