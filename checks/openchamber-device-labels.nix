# The managed device identity is a label, and upstream truncates labels at 80 characters. A device
# id that does not fit is stored under a different id; the revoke reconciler then treats the device
# as unmanaged and revokes it, and re-enrollment cannot repair a truncated identity. This fixture
# proves the boundary against the real client-auth runtime, the real mint helper and the real revoke
# helper, including revocation and re-enrollment, without touching a user device.
{
  pkgs,
  ...
}:
pkgs.runCommandLocal "openchamber-device-labels-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_24 ];
  }
  ''
    node ${./openchamber-device-labels.test.mjs} \
      ${../features/dev/openchamber/mint.mjs} \
      ${../features/dev/openchamber/revoke.mjs} \
      ${pkgs.openchamber.passthru.core}/lib/openchamber/packages/web/server/lib/client-auth/remote-clients.js
    touch $out
  ''
