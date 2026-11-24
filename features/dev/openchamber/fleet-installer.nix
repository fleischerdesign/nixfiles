{ pkgs }:
pkgs.writeShellApplication {
  name = "openchamber-fleet-extension-install";
  runtimeInputs = [ pkgs.python3 ];
  text = ''
    exec ${pkgs.python3}/bin/python ${
      builtins.path {
        path = ./fleet_install.py;
        name = "fleet_install.py";
      }
    } "$@"
  '';
}
