# The client adapter is what turns the token-free registry into a working host entry. A regression
# here either loses the user's unmanaged settings, rotates a valid token, or re-enrolls a device whose
# grant was removed. This runs the shipped adapter against the real server and a real settings file.
#
# Opt-in integration check (`nix build .#integrationChecks.<system>.openchamber-provision`), not part
# of `nix flake check`: it pulls the server's 2.4 GB runtime closure and starts a process, which the
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
pkgs.runCommand "openchamber-provision-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    node ${./openchamber-provision.test.mjs} \
      ${pkgs.openchamber}/bin/openchamber \
      ${openchamber.mintPackage}/bin/openchamber-mint \
      ${../../features/dev/openchamber/provision.mjs} \
      ${pkgs.nodejs_22}/bin/node
    touch $out
  ''
