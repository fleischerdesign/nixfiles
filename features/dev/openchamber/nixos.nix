{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.openchamber;
  ownHost = config.my.topology.hosts.${config.networking.hostName} or null;
in
{
  imports = [ ./mesh.nix ];

  options.my.features.dev.openchamber = {
    enable = lib.mkEnableOption "OpenChamber workspace for Home Manager users";

    web.enable = lib.mkEnableOption "OpenChamber web and CLI interface";
    desktop.enable = lib.mkEnableOption "OpenChamber desktop interface";

    server = {
      enable = lib.mkEnableOption "a headless OpenChamber server bound to this host mesh address";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "TCP port the headless server listens on, on the mesh address of the host.";
      };

      apiOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Serve the API without the browser interface assets - the headless mode a native client
          needs and nothing more. Serving the browser interface requires disabling this explicitly.
        '';
      };

      publish = {
        enable = lib.mkEnableOption "a public name for this instance, terminated by the ingress";

        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "chamber";
          description = "Subdomain under the site zone that the published instance answers on.";
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Use the upstream machine policy so every surface keeps Nix's CLI and
      # credentials instead of offering an independent OpenCode installation.
      environment.etc."openchamber/policy.json".text = builtins.toJSON {
        opencodeBinary = "${config.my.features.dev.opencode.package}/bin/opencode";
      };
    })
    {
      assertions =
        lib.optionals cfg.enable [
          {
            assertion = config.my.features.dev.opencode.enable;
            message = "OpenChamber requires the OpenCode feature on this host.";
          }
          {
            assertion = cfg.web.enable || cfg.desktop.enable || cfg.server.enable;
            message = "OpenChamber must enable at least one interface.";
          }
          {
            assertion = !cfg.desktop.enable || pkgs.stdenv.hostPlatform.system == "x86_64-linux";
            message = "The OpenChamber desktop package is available only on x86_64-linux.";
          }
          {
            # A name is put on a running instance, so publishing without serving would leave a
            # virtual host in front of nothing.
            assertion = !cfg.server.publish.enable || cfg.server.enable;
            message = "OpenChamber cannot publish an instance it does not serve.";
          }
        ]
        ++ lib.optionals (cfg.enable && cfg.server.enable) [
          {
            # The bind address and the firewall rule are both derived from the inventory entry, so
            # a host without a mesh address cannot silently serve on the wrong one.
            assertion = ownHost != null && ownHost.wireguardIpv4 != null;
            message = "The OpenChamber server binds the mesh address, but ${config.networking.hostName} declares no wireguardIpv4.";
          }
        ];

      home-manager.sharedModules = [ ./home.nix ];
    }

    # The port is opened for the mesh and for the mesh alone, and only while the feature is on:
    # the firewall renders it from the contract like every other permission in this fleet. With
    # the feature off nothing is declared, so no service entry is left behind to offer nothing.
    (lib.mkIf (cfg.enable && cfg.server.enable) {
      # OpenChamber refuses to bind a reachable address without a UI password, and it is right to:
      # the mesh is reachable from every node. The signing secret matters for the same reason in
      # reverse: a key minted fresh at every start would invalidate every paired device on every
      # restart. Both are declared here, with the host's own key, and owned by the operator so the
      # user service can read them. A missing key fails the deploy loudly instead of leaving a unit
      # that restarts forever.
      sops.secrets."openchamber/ui_password" = {
        owner = config.my.user.primary;
        mode = "0400";
      };
      sops.secrets."openchamber/jwt_secret" = {
        owner = config.my.user.primary;
        mode = "0400";
      };

      my.contracts.provides.openchamber.endpoints.http = {
        port = cfg.server.port;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
      };

      # The instance is a user service. On a server nobody is logged in at all, so it has to outlive
      # any login; on a personal computer the session owns it like every other user service, and a
      # logged-out computer does not serve the peer - the requirement is a fact of the host class,
      # which is why it is derived from the role instead of assumed from the enable switch.
      users.users.${config.my.user.primary}.linger = lib.mkIf (config.my.role == "server") (
        lib.mkDefault true
      );
    })

    # A name is what makes the instance reachable from a network that is not the mesh, which is the
    # reason to publish it at all. The ingress terminates TLS, keeps the sign-on in front of
    # everything that is not the API, and the instance authenticates every API call itself.
    (lib.mkIf (cfg.enable && cfg.server.enable && cfg.server.publish.enable) {
      my.contracts.provides.openchamber.publications.web = {
        scope = "public";
        endpoint = "http";
        auth = "authentik";
        subdomain = cfg.server.publish.subdomain;

        # The callers of this name are applications, not browsers. Every route under /api answers
        # 401 without a device token (measured: 425 of 430 routes), and the pairing call that
        # issues the token carries its own single-use secret - a sign-on redirect in front of it
        # would block exactly the step that connects a device. So the API speaks for itself while
        # everything else on the host stays behind the sign-on. A narrower list of paths would
        # break the next app update that adds a route.
        unauthenticatedPaths = [ "/api/*" ];

        # The audience edge is the whole authentication boundary, so the name terminates there and
        # nowhere else: forward-auth asks the central outpost, which answers on the authentik host
        # alone, and a second vhost next to the instance would carry the name without a working
        # gate. The instance is reached from the mesh by its overlay address, which is what the
        # endpoint already opens.
        ingressOnly = true;

        # The instance runs commands and reads files on a real machine, so its audience is the same
        # one that administers the fleet - stated, never inferred.
        accessGroups = [ "infra-admins" ];

        # Live traffic in both directions: the message and terminal transports are WebSockets and
        # the event feeds are server-sent events. A proxy that buffers either turns a live session
        # into one that answers after the fact, so the response is flushed as it arrives and the
        # read stays open far longer than a request.
        proxyOptions = ''
          flush_interval -1
          transport http {
            read_timeout 3600s
            write_timeout 3600s
          }
        '';
      };
    })
  ];
}
