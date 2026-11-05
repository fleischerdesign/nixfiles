# remote-exec - one Gateway-authored source snapshot, one executor attempt.
#
# The program is a thin Python CLI so capture, manifest verification, attempt
# layout and process ownership are testable without a second machine. Its
# runtime tools are named here, not inherited from the caller's PATH.
{ pkgs }:
let
  runtimeInputs = with pkgs; [
    python3
    git
    rsync
    openssh
    coreutils
    findutils
  ];
  package = pkgs.writeShellApplication {
    name = "remote-exec";
    runtimeInputs = runtimeInputs;
    text = ''
      export PYTHONPATH=${./.}''${PYTHONPATH:+:$PYTHONPATH}
      exec python3 -m remote_exec "$@"
    '';
  };
in
package.overrideAttrs (previous: {
  passthru = (previous.passthru or { }) // {
    tests =
      pkgs.runCommand "remote-exec-tests"
        {
          nativeBuildInputs = runtimeInputs;
          REMOTE_EXEC_BIN = "${package}/bin/remote-exec";
        }
        ''
          cp -r ${./.} "$TMPDIR/src"
          chmod -R u+w "$TMPDIR/src"
          cd "$TMPDIR/src"
          PYTHONPATH="$PWD" python3 -m unittest discover -s tests -v
          touch "$out"
        '';
  };
})
