# Caddy reorders directives, so the order in the generated Caddyfile is not the order Caddy runs:
# `forward_auth` executes before `request_header` regardless of how they are written. A block that
# strips client-supplied identity headers and then authenticates therefore deletes the trusted
# headers the auth step copied, and every downstream trusted-proxy consumer sees none. The only
# honest measurement is Caddy's own adapted output, which this check reads for each forward-auth
# block on the ingress.
{
  pkgs,
  self,
  ...
}:
let
  host = self.nixosConfigurations.cld-edge-01;
  publications = builtins.filter (pub: pub.auth == "authentik" && pub.unauthenticatedPaths != [ ]) (
    builtins.concatMap (contract: builtins.attrValues contract.publications) (
      builtins.attrValues self.nixosConfigurations.cld-ops-01.config.my.contracts.provides
    )
  );
  exemptions = pkgs.writeText "caddy-auth-exemptions.json" (
    builtins.toJSON (
      map (pub: {
        domain = pub.canonicalDomain;
        paths = pub.unauthenticatedPaths;
      }) publications
    )
  );
in
pkgs.runCommand "caddy-auth-order-check"
  {
    nativeBuildInputs = [
      pkgs.caddy
      pkgs.python3
    ];
  }
  ''
    set -euo pipefail
    caddy adapt --config ${host.config.services.caddy.configFile} --adapter caddyfile > adapted.json
    python3 ${./caddy-auth-order.py} adapted.json ${exemptions}
    touch $out
  ''
