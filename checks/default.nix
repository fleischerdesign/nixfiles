# The check surface. Discovered, not listed: `checks/<name>.nix` is a check and
# `checks/integration/<name>.nix` is one that boots a service. The file name is the output name, so
# `nix build .#checks.x86_64-linux.<name>` names the file the statement lives in.
#
# The rules are in AGENTS.md ("Where an assertion belongs"): a check that cannot fail on a plausible
# change is not a check. This file only finds them.
checkArgs:
let
  discovery = import ../lib/checks.nix { inherit (checkArgs) lib; };
in
{
  checks = discovery.discover ./. checkArgs;
  integration = discovery.discover ./integration checkArgs;
}
