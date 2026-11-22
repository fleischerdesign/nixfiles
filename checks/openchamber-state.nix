# A switch loses interactive connections or resets a healthy account when declared peers or keys change.
{ pkgs, ... }:
let
  file =
    path:
    builtins.path {
      inherit path;
      name = baseNameOf path;
    };
in
pkgs.runCommand "openchamber-state" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python ${file ./fixtures/openchamber/state.py} \
    ${file ../features/dev/openchamber/reconcile.py} \
    ${file ../features/dev/openchamber/credentials.py}
  touch "$out"
''
