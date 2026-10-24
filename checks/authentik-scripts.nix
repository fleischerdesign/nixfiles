# The apply and the drift report are Python embedded in the module and executed only on the host; a
# syntax error in either would otherwise be found by a deploy, which is a fleet-wide failure. This
# compiles them with the same interpreter the host runs, so a pull request finds it instead.
{
  pkgs,
  lib,
  self,
  blueprintHosts,
  ...
}:
let
  units = [
    "authentik-blueprints-apply"
    "authentik-drift-report"
    "authentik-directory-report"
  ];
  scriptOf =
    name: unit:
    builtins.substring 5 1000000
      self.nixosConfigurations.${name}.config.systemd.services.${unit}.serviceConfig.StandardInput;
  scripts = lib.unique (lib.concatMap (name: map (scriptOf name) units) blueprintHosts);
in
pkgs.runCommandLocal "authentik-scripts-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    for script in ${lib.concatStringsSep " " scripts}; do
      python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="out.pyc", doraise=True)' "$script"
    done
    echo "ok: ${toString (lib.length scripts)} embedded authentik script(s) compile" > $out
  ''
