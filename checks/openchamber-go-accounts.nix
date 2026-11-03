# Retiring the selected managed Go account used to delete it before selecting a replacement, so a
# failed activation left the integration with no active credential and every later run skipped the
# repair. The same failure dropped the user's selection when the seed was interrupted between the
# delete and the activate.
#
# Named failure: an interrupted or failed retirement leaves OpenCode Go with no active account, or a
# rerun silently refuses to heal it - and a manual/foreign selection must never be replaced.
#
# This is a fixture, not a runtime acceptance test: a fake OpenChamber API on loopback plus a real
# node:sqlite credential table, with no server, no keys and no network.
{
  pkgs,
  ...
}:
pkgs.runCommandLocal "openchamber-go-accounts-check"
  {
    nativeBuildInputs = [ pkgs.nodejs ];
  }
  ''
    node ${./openchamber-go-accounts.test.mjs} ${../features/dev/openchamber/go-accounts.mjs}
    touch $out
  ''
