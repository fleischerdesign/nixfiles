{ pkgs }:
let
  piRoot = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
  package = pkgs.writeShellApplication {
    name = "pi-auth-reconcile";
    text = ''
      exec ${pkgs.nodejs}/bin/node ${./auth-reconcile.mjs} ${piRoot} "$@"
    '';
  };
in
{
  inherit package;
  check = pkgs.runCommand "pi-auth-check" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    export PI_AUTH_RECONCILER=${package}/bin/pi-auth-reconcile
    export PI_PACKAGE_ROOT=${piRoot}
    export PI_AUTH_JQ=${pkgs.jq}/bin/jq
    node --test ${./auth-reconcile.test.mjs}
    touch "$out"
  '';
}
