# HTTP ingress policy of a publication; no listener or network implementation lives here.
{ lib }:
{
  options = {
    ingress = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the HTTP ingress terminates this publication - a Caddy virtual host and the
        certificate that goes with it. A publication another component terminates itself (a
        resolver's DNS-over-TLS door) sets this to false: its name is still projected
        into public DNS and its port into the host firewall, but no virtual host and no
        ingress certificate are created for it.
      '';
    };

    auth = lib.mkOption {
      type = lib.types.enum [
        "none"
        "authentik"
        "proxy-pass"
        "oidc"
      ];
      default = "none";
      description = "Authentication enforcement policy";
    };

    publicExempt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Reason a public publication may run with auth = \"none\" (invariant I9).";
    };

    unauthenticatedPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Path globs bypassing edge auth for self-authenticating webhooks/tokens";
    };

    machineClientsBypassAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Bypass forward-auth for non-browser WebSocket upgrades (e.g. device/node tokens)";
    };

  };
}
