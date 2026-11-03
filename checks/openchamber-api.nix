# The server's client-management routes are the only place a device token is minted. A mock cannot
# prove the session cookie is accepted, the dedupe mint replaces the old token, or that removing the
# grant blocks re-enrollment; this runs the built server, the shipped mint helper and the shipped
# revoke helper over real HTTP.
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
