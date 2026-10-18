{
  config,
  lib,
  pkgs,
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
  camera = cfg.camera.enable;
  # The gateway's Control UI as a desktop launcher. Derived rather than declared twice:
  # the URL comes from the gateway host's publication, and the launcher exists only where
  # the desktop webapp feature is enabled and the gateway is actually published.
  webapps =
    lib.optionalAttrs
      (endpoint.publicUrl != null && (config.my.features.desktop.webapps.enable or false))
      {
        openclaw = {
          displayName = "OpenClaw";
          url = endpoint.publicUrl;
          icon = ../../../../media/openclaw.png;
          comment = "OpenClaw Gateway Control UI";
          categories = [
            "Network"
            "Utility"
          ];
          wmClass = "openclaw";
        };
      };
in
{
  options.my.features.services.openclaw.node = {
    enable = lib.mkEnableOption "native OpenClaw session hosting for the primary Home Manager user";
    camera.enable = lib.mkEnableOption "camera capture through this node (requires a V4L2 camera and FFmpeg)";
  };

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
      (import ./home.nix { inherit endpoint camera webapps; })
    ];

    # Camera capture opens /dev/video*, whose device nodes belong to the video group. The
    # group is declared with mkDefault so it merges into the role's group list instead of
    # replacing it.
    my.user.extraGroups = lib.mkMerge [
      (lib.mkIf camera (lib.mkDefault [ "video" ]))
    ];

    # The File Transfer plugin runs its archive builder as /usr/bin/tar on Unix: a
    # hardcoded FHS path NixOS does not provide, which makes every dir.fetch fail with
    # "tar command failed". Materialise it for the node; no other file command reaches
    # for an FHS binary.
    systemd.tmpfiles.rules = [
      "L+ /usr/bin/tar - - - - ${pkgs.gnutar}/bin/tar"
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
