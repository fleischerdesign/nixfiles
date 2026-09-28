# Named observations of a service. Targets reference endpoint ids; addresses and ports are resolved
# by the collector adapter, never copied into a probe or a scrape declaration.
{
  config,
  lib,
  ...
}:
let
  endpointIdentifiers = import ../endpoints/lib/identifiers.nix { };
  probe = lib.types.submodule (submod: {
    options = {
      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "Endpoint id within this service.";
      };
      kind = lib.mkOption {
        type = lib.types.enum [
          "http"
          "tcp"
        ];
        description = "Protocol used by the blackbox exporter.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Health path for HTTP probes.";
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = if submod.config.kind == "tcp" then "Infrastructure" else "HTTP";
        description = "Operator-facing probe category.";
      };
    };
  });
  scrape = lib.types.submodule {
    options = {
      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "Endpoint id providing the metrics listener.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/metrics";
        description = "HTTP metrics path.";
      };
      jobName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Explicit stable Prometheus job identity, when different from the endpoint name.";
      };
    };
  };
  violations = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      let
        check =
          kind: name: observation:
          let
            where = "${service}.telemetry.${kind}.${name}";
            ep = contract.endpoints.${observation.endpoint} or null;
            isHttp = kind == "scrapes" || observation.kind == "http";
          in
          lib.optional (ep == null) "${where}: unknown endpoint '${observation.endpoint}'"
          ++ lib.optionals (ep != null) (
            lib.optional (
              isHttp && ep.applicationProtocol != "http"
            ) "${where}: HTTP observation requires an HTTP endpoint"
            ++ lib.optional (!isHttp && ep.protocol == "udp") "${where}: TCP probe requires a TCP endpoint"
          )
          ++ lib.optional (isHttp && !lib.hasPrefix "/" observation.path) "${where}: path must start with '/'"
          ++ lib.optional (
            kind == "scrapes" && observation.jobName == ""
          ) "${where}: scrape job name must not be empty";
      in
      lib.concatLists (lib.mapAttrsToList (check "probes") contract.telemetry.probes)
      ++ lib.concatLists (lib.mapAttrsToList (check "scrapes") contract.telemetry.scrapes)
    ) config.my.contracts.provides
  );
  # A Prometheus job name is fleet-visible series identity: two scrapes sharing one merge into a
  # single job, so the effective name (explicit override, else the endpoint's fleet name) must be
  # unique across this host's services. Same-host grouping is what merges; other hosts group by
  # the same name on purpose.
  effectiveJobNames = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      lib.mapAttrsToList (
        _: scrape:
        if scrape.jobName != null then
          scrape.jobName
        else
          endpointIdentifiers.endpointName service scrape.endpoint
      ) contract.telemetry.scrapes
    ) config.my.contracts.provides
  );
  duplicateJobNames = lib.unique (
    lib.filter (
      name: builtins.length (lib.filter (n: n == name) effectiveJobNames) > 1
    ) effectiveJobNames
  );
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.telemetry = {
          probes = lib.mkOption {
            type = lib.types.attrsOf probe;
            default = { };
            description = "Named HTTP and TCP observations of service endpoints.";
          };
          scrapes = lib.mkOption {
            type = lib.types.attrsOf scrape;
            default = { };
            description = "Named Prometheus scrapes of HTTP endpoints.";
          };
        };
      }
    );
  };
  config.assertions = [
    {
      assertion = violations == [ ];
      message = "invalid telemetry declarations:\n${lib.concatStringsSep "\n" violations}";
    }
    {
      assertion = duplicateJobNames == [ ];
      message = "duplicate Prometheus job names: ${lib.concatStringsSep ", " duplicateJobNames}";
    }
  ];
}
