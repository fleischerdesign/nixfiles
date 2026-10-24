# Lint: no unused or misspelled Nix. The disabled rules live in statix.toml, next to the tree.
{ pkgs, ... }:
pkgs.runCommandLocal "statix-check"
  {
    nativeBuildInputs = [ pkgs.statix ];
  }
  ''
    statix check --config ${../statix.toml} ${../.}
    touch $out
  ''
