# The check surface. Discovered, not listed: `checks/<name>.nix` is a check and the file name is the
# output name, so `nix build .#checks.x86_64-linux.<name>` names the file the statement lives in.
#
# The rules are in AGENTS.md ("Where an assertion belongs"): a check that cannot fail on a plausible
# change is not a check, and a statement about another repository's component is tested there. This
# file only finds the checks.
checkArgs: (import ../lib/checks.nix { inherit (checkArgs) lib; }).discover ./. checkArgs
