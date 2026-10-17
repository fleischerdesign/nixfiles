{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.openclaw.node;
  fleetConfigs = import ../../../../lib/fleet-configs.nix { inherit lib; };
  systems = fleetConfigs.systems config;
  gatewayHost = fleetConfigs.uniqueHost {
    inherit systems;
    matches = host: host.my.features.services.openclaw.gateway.enable or false;
    role = "OpenClaw gateway";
  };
  gateway = systems.${gatewayHost}.config;
  domain = gateway.my.contracts.provides.openclaw.publications.web.canonicalDomain or null;
  meshAddress = config.my.topology.hosts.${gatewayHost}.wireguardIpv4 or null;
  ingress = config.my.topology.hosts.${config.my.topology.ingressHost};
  # Prefer the published TLS endpoint so join URLs and supervised reconnects use
  # the same gateway scope. Without publication, enroll with a mesh setup code.
  endpoint = {
    host = if domain != null then domain else meshAddress;
    port = if domain != null then 443 else gateway.my.features.services.openclaw.gateway.port;
    tls = domain != null;
    publicUrl = if domain != null then "https://${domain}" else null;
  };
in
{
  options.my.features.services.openclaw.node.enable =
    lib.mkEnableOption "native OpenClaw session hosting for the primary Home Manager user";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.my.features.services.openclaw.gateway.enable;
        message = "The OpenClaw gateway host must not also run the fleet node service.";
      }
      {
        assertion = builtins.hasAttr config.my.user.primary config.home-manager.users;
        message = "OpenClaw node requires Home Manager for the primary user.";
      }
      {
        assertion = endpoint.host != null;
        message = "OpenClaw node requires a published gateway domain or a gateway mesh address.";
      }
    ];

    home-manager.sharedModules = [
      (import ./home.nix { inherit endpoint; })
    ];

    # A node on the proxy host must not present the proxy's trusted mesh IP
    # as its own forwarded client address: OpenClaw correctly rejects that
    # indistinguishable chain. Use this host's public address with the same
    # TLS name, without widening proxy trust or accepting loopback identities.
    networking.hosts = lib.optionalAttrs (
      config.networking.hostName == config.my.topology.ingressHost
      && domain != null
      && ingress.ipv4 != null
    ) { ${ingress.ipv4} = [ domain ]; };

    users.users.${config.my.user.primary}.linger = lib.mkIf (config.my.role == "server") (
      lib.mkDefault true
    );
  };
}
