# HTTP ingress policy of a publication; no listener or network implementation lives here.
{ lib }:
{
  options = {
    ingressOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Terminate this public publication only on the central ingress, including LAN and overlay DNS answers. Used when the ingress network identity is an authentication boundary.";
    };
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

    stripRequestHeaders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Request header names or globs the ingress removes from client requests before
        authentication, so a downstream trusted-proxy consumer can never read a value the client
        chose. The authentication integration's own identity headers are stripped by the ingress
        itself; this option is for headers a particular publication owns.
      '';
    };

  };
}
