# The portable extension is built in openchamber-fleet; Nix only reserves the built-in ID.
{
  pkgs,
  inputs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  controller = inputs.openchamber-fleet.packages.${system}.controller;
in
pkgs.runCommand "openchamber-builtin-fleet" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python ${./prepare-fleet-extension.py} \
    ${controller}/lib/node_modules/openchamber-fleet/extensions/openchamber $out
''
