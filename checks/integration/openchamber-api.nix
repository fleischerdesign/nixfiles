# The server's client-management routes are the only place a device token is minted. A mock cannot
# prove the session cookie is accepted, the dedupe mint replaces the old token, or that removing the
# grant blocks re-enrollment; this runs the built server, the shipped mint helper and the shipped
# revoke helper over real HTTP.
#
# Opt-in integration check (`nix build .#integrationChecks.<system>.openchamber-api`), not part of
# `nix flake check`: it pulls the server's 2.4 GB runtime closure and starts a process, which the
# host build already pays for once and the unconditional gate should not pay twice.
{
  pkgs,
  self,
  ...
}:
let
  server = self.nixosConfigurations.cld-ops-01.config;
  openchamber = server.my.features.dev.openchamber.server;
in
pkgs.runCommand "openchamber-api-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    node ${./openchamber-api.test.mjs} \
      ${pkgs.openchamber}/bin/openchamber \
      ${openchamber.mintPackage}/bin/openchamber-mint \
      ${openchamber.revokePackage}/bin/openchamber-revoke
    touch $out
  ''
