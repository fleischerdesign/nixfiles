{
  pkgs,
  lib,
  self,
  ...
}:
let
  makeTarget = import ../features/system/networking/cloudflare/target.nix;
  fakeReconciler = pkgs.writeShellApplication {
    name = "cloudflare-sync";
    text = ''
      command -v sops > /dev/null
      printf '%s\n' "$@" > "$CALL_LOG"
      exit "''${RECONCILER_EXIT:-0}"
    '';
  };
  fixture = makeTarget {
    inherit pkgs lib;
    reconciler = fakeReconciler;
  };
  target = self.nodTargets.cloudflare.package;
in
pkgs.runCommandLocal "cloudflare-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  # Build and inspect the published artifact. Unsupported actions must stop
  # before any credentials or API calls are touched, even on the real target.
  python3 ${./cloudflare.py} \
    ${../features/system/networking/cloudflare/sync.py} \
    ${fixture}/bin/activate \
    ${target}/bin/activate
  touch "$out"
''
