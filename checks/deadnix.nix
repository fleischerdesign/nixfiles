# Lint: nothing is declared that nothing uses.
{ pkgs, ... }:
pkgs.runCommandLocal "deadnix-check"
  {
    nativeBuildInputs = [ pkgs.deadnix ];
  }
  ''
    deadnix --fail ${../.}
    touch $out
  ''
