# remote-exec - one Gateway-authored source snapshot, one supervised attempt.
#
# The program is a Python CLI so capture, manifest verification, attempt
# ownership, supervision and selection are testable without a second machine.
# Runtime tools are named here, not inherited from the caller's PATH.
{ pkgs, lib }:
let
  # Content-address only this application's subtree. A path literal into the
  # flake source would hash the whole repository, so a documentation edit would
  # rebuild the tool and untracked bytecode could leak into the store.
  source = builtins.path {
    path = ./.;
    name = "remote-exec-source";
    filter =
      path: _type:
      let
        base = baseNameOf (toString path);
      in
      base != "__pycache__" && !(lib.hasSuffix ".pyc" base);
  };
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
      export PYTHONPATH=${source}''${PYTHONPATH:+:$PYTHONPATH}
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
          inherit source;
        }
        ''
          test ! -e "$source/remote_exec/__pycache__"
            cp -r "$source" "$TMPDIR/src"
            chmod -R u+w "$TMPDIR/src"
            cd "$TMPDIR/src"
            PYTHONPATH="$PWD" python3 -m unittest discover -s tests -v
            touch "$out"
        '';
  };
})
