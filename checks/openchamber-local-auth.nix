# Enabling desktop network protection without its native Local token locks the owner out.
{ pkgs, ... }:
pkgs.runCommandLocal "openchamber-local-auth-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; } ''
  node     ${./openchamber-local-auth.test.mjs}     ${../features/dev/openchamber/provision.mjs}     ${pkgs.openchamber.passthru.core}/lib/openchamber/packages/web/server/lib/client-auth/remote-clients.js
  touch $out
''
