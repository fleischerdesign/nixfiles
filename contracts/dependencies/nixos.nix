# contracts/dependencies/nixos.nix
# Declarative Dependency & Consumption Contract Specification (Inversion of Control).
# Services declare what external capabilities/databases/caches they require ('consumes')
# rather than database/cache providers having to hardcode consumer lists ('provides').
{
  config,
  lib,
  fleetConfigs,
  ...
}:

let
  # PostgreSQL consumer specification
  postgresConsumerSubmodule = lib.types.submodule (submod: {
    options = {
      database = lib.mkOption {
        type = lib.types.str;
        default = submod.config._module.args.name;
        description = "Name of the PostgreSQL database required by the service";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = submod.config.database;
        description = "Name of the PostgreSQL database user owning the schema";
      };

      ensureDBOwnership = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Grant ownership of the database to the specified user";
      };
    };
  });

  consumerContractSubmodule = lib.types.submodule {
    options = {
      postgresql = lib.mkOption {
        type = lib.types.attrsOf postgresConsumerSubmodule;
        default = { };
        description = "PostgreSQL databases required by this service";
      };

    };
  };

  # Extract active postgres dependencies across all services on this host
  allConsumes = config.my.contracts.consumes or { };

  allLocalPostgresNeeds = lib.concatLists (
    lib.mapAttrsToList (
      _svcName: consumer:
      lib.mapAttrsToList (_depName: pg: {
        inherit (pg) database user ensureDBOwnership;
      }) (consumer.postgresql or { })
    ) allConsumes
  );

  uniqueDatabases = lib.unique (map (p: p.database) allLocalPostgresNeeds);
  uniqueUsers = lib.unique (
    map (p: {
      name = p.user;
      inherit (p) ensureDBOwnership;
    }) allLocalPostgresNeeds
  );
  # `dependsOn` names fleet-wide service ids - the portal projection resolves them across hosts,
  # so the reference is validated against the whole fleet, not just this host's services.
  flakeConfigurations = fleetConfigs.systems config;
  fleetServices = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: hostCfg: builtins.attrNames (fleetConfigs.providesOf hostCfg)
      ) flakeConfigurations
    )
  );
  invalidDependencies = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      lib.concatMap (
        dependency:
        lib.optional (
          builtins.match "[a-z0-9][a-z0-9-]*" dependency == null
        ) "${service}.dependsOn: '${dependency}' is not a service id"
        ++ lib.optional (
          builtins.match "[a-z0-9][a-z0-9-]*" dependency != null && !(builtins.elem dependency fleetServices)
        ) "${service}.dependsOn: '${dependency}' names no declared service"
      ) contract.dependsOn
    ) config.my.contracts.provides
  );
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.dependsOn = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Other services this one needs to work, named by service id rather than host.";
        };
      }
    );
  };

  options.my.contracts.consumes = lib.mkOption {
    type = lib.types.attrsOf consumerContractSubmodule;
    default = { };
    description = "Service-level inbound dependencies (Databases, Caches, Brokers) requested by local features";
  };

  # Inversion of Control Projection:
  # When PostgreSQL is enabled locally on this host, automatically provision
  # all databases and users declared by consumers on this host!
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = invalidDependencies == [ ];
          message = "invalid service dependencies:\n${lib.concatStringsSep "\n" invalidDependencies}";
        }
      ];
    }
    (lib.mkIf (config.services.postgresql.enable or false) {
      services.postgresql = {
        ensureDatabases = uniqueDatabases;
        ensureUsers = uniqueUsers;
      };
    })
  ];
}
