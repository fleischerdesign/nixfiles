# The built-in registry merge preserves upstream entries and rejects collisions.
{ pkgs, ... }:
let
  file =
    path:
    builtins.path {
      inherit path;
      name = baseNameOf path;
    };
in
pkgs.runCommand "openchamber-registry" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python ${file ./fixtures/openchamber/registry.py} \
    ${file ../features/dev/openchamber/merge-registry.py}
  touch "$out"
''
