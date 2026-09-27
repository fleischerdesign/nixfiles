# contracts/endpoints/nixos.nix
# A listener: where a service accepts connections and on which protocol. It owns no DNS name,
# no ingress, no audience and no presentation - those are declarations that reference it.
{
  config,
  lib,
  ...
}:
let
  endpointContractSubmodule = lib.types.submodule (submod: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = "Internal network port the service listens on";
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "tcp"
          "udp"
          "both"
        ];
        default = "tcp";
        description = "Transport layer protocol";
      };

      applicationProtocol = lib.mkOption {
        type = lib.types.strMatching "[a-z][a-z0-9-]*";
        default = if submod.config.protocol == "udp" then "other" else "http";
        description = ''
          Protocol spoken by this listener, independently of transport. The TCP default preserves
          existing HTTP listeners; non-HTTP listeners must name their application protocol. A named
          application protocol is what keeps an HTTP probe or scrape from being inferred for a
          listener that does not speak HTTP.
        '';
      };

      directAccess = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open this port directly in the host firewall";
        };

        protocol = lib.mkOption {
          type = lib.types.enum [
            "tcp"
            "udp"
            "both"
          ];
          default = submod.config.protocol;
          description = "Network protocol to open in the firewall. It follows the listener's own transport by default; the assertion below rejects anything else.";
        };

        interface = lib.mkOption {
          type = lib.types.enum [
            "all"
            "wireguard"
            "local"
          ];
          default = "all";
          description = "Network interface to bind the firewall rule to (all, wireguard, or local)";
        };

        from = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Trust levels whose nodes may reach this port over the mesh. An empty list means every
            level the topology declares. It restricts, never opens: the port is opened by
            `interface`, and this says who of the mesh may actually use it.
          '';
        };
      };

      localUrl = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        description = "Loopback URL of this listener, for observations that run on the same host.";
      };
    };

    config = {
      localUrl = "http://127.0.0.1:${toString submod.config.port}";
    };
  });
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.endpoints = lib.mkOption {
          type = lib.types.attrsOf endpointContractSubmodule;
          default = { };
          description = "Listeners this service exposes. A listener is not a publication.";
        };
      }
    );
  };

  # `directAccess.protocol` is not a second transport: it must name the listener's own protocol.
  # A dual-stack listener opened TCP-only would serve UDP into a closed firewall - silently, because
  # both options evaluate. Narrowing a protocol is a separate explicit mechanism, not a mismatch.
  config.assertions = [
    {
      assertion = lib.all (
        contract:
        lib.all (ep: !ep.directAccess.enable || ep.directAccess.protocol == ep.protocol) (
          lib.attrValues contract.endpoints
        )
      ) (lib.attrValues config.my.contracts.provides);
      message = "an endpoint's directAccess.protocol must equal its transport protocol";
    }
  ];
}
