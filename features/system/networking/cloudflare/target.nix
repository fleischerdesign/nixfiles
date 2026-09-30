# nod's activation protocol is separate from the reconciler's operational CLI.
{
  pkgs,
  lib,
  reconciler,
}:
pkgs.writeShellApplication {
  name = "activate";
  # Agentless activation runs on the operator's machine, where the reconciler
  # reads its credential from SOPS unless an explicit environment token exists.
  runtimeInputs = [ pkgs.sops ];
  text = ''
    if [ "$#" -ne 1 ]; then
      echo 'Usage: activate switch' >&2
      exit 2
    fi
    case "$1" in
      switch)
        exec ${lib.getExe' reconciler "cloudflare-sync"} --prune
        ;;
      *)
        echo "Cloudflare activation: unsupported action '$1'; only switch is supported" >&2
        exit 2
        ;;
    esac
  '';
}
