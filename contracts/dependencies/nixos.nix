# contracts/dependencies/nixos.nix
# Declarative Dependency & Consumption Contract Specification (Inversion of Control).
# Services declare what external capabilities/databases/caches they require ('consumes')
# rather than database/cache providers having to hardcode consumer lists ('provides').
{
  config,
  lib,
  pkgs,
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
        description = "Make the declared role own this database, including when database and role names differ";
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
      service: consumer:
      lib.mapAttrsToList (dependency: pg: {
        inherit service dependency;
        inherit (pg) database user ensureDBOwnership;
      }) (consumer.postgresql or { })
    ) allConsumes
  );

  uniqueDatabases = lib.unique (map (p: p.database) allLocalPostgresNeeds);
  roleNames = lib.unique (map (need: need.user) allLocalPostgresNeeds);
  uniqueUsers = map (name: {
    inherit name;
    ensureDBOwnership = lib.any (
      need: need.user == name && need.ensureDBOwnership && need.database == name
    ) allLocalPostgresNeeds;
  }) roleNames;
  ownershipNeeds = lib.filter (
    need: need.ensureDBOwnership && need.database != need.user
  ) allLocalPostgresNeeds;
  ownershipHandoffs = lib.unique (
    map (need: {
      inherit (need) database user;
    }) ownershipNeeds
  );
  ownershipConsumers = lib.unique (map (need: need.service) ownershipNeeds);
  ownedDatabaseNames = lib.unique (
    map (need: need.database) (lib.filter (need: need.ensureDBOwnership) allLocalPostgresNeeds)
  );
  conflictingDatabaseOwners = lib.concatMap (
    database:
    let
      owners = lib.unique (
        map (need: need.user) (
          lib.filter (need: need.database == database && need.ensureDBOwnership) allLocalPostgresNeeds
        )
      );
    in
    lib.optional (builtins.length owners > 1) "${database}: ${lib.concatStringsSep ", " owners}"
  ) ownedDatabaseNames;
  invalidPostgresqlNames = lib.filter (
    need:
    builtins.match "[A-Za-z_][A-Za-z0-9_-]*" need.database == null
    || builtins.match "[A-Za-z_][A-Za-z0-9_-]*" need.user == null
    || builtins.match "[a-z0-9][a-z0-9-]*" need.service == null
  ) allLocalPostgresNeeds;
  missingPostgresql = allLocalPostgresNeeds != [ ] && !(config.services.postgresql.enable or false);
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
          assertion = !missingPostgresql;
          message = "PostgreSQL is consumed on ${config.networking.hostName}, but no local PostgreSQL provider is enabled";
        }
        {
          assertion = invalidPostgresqlNames == [ ];
          message = "PostgreSQL database and role names must match [A-Za-z_][A-Za-z0-9_-]*: ${
            lib.concatStringsSep ", " (
              map (
                need: "${need.service}.${need.dependency} (${need.database}, ${need.user})"
              ) invalidPostgresqlNames
            )
          }";
        }
        {
          assertion = conflictingDatabaseOwners == [ ];
          message = "PostgreSQL databases may have one declared owner: ${lib.concatStringsSep ", " conflictingDatabaseOwners}";
        }
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

      systemd.services = lib.mkMerge (
        [
          (lib.mkIf (ownershipHandoffs != [ ]) {
            postgresql-contract-ownership = {
              description = "Apply database ownership declared by service contracts";
              after = [ "postgresql.service" ];
              requires = [ "postgresql.service" ];
              wantedBy = [ "multi-user.target" ];
              before = map (service: "${service}.service") ownershipConsumers;
              serviceConfig = {
                Type = "oneshot";
                User = "postgres";
                ExecStart = pkgs.writeShellScript "postgresql-contract-ownership" ''
                  set -euo pipefail
                  ${lib.concatMapStringsSep "\n" (need: ''
                    ${config.services.postgresql.package}/bin/psql --dbname=postgres --set=ON_ERROR_STOP=1 --command='ALTER DATABASE "${need.database}" OWNER TO "${need.user}";'
                  '') ownershipHandoffs}
                '';
              };
            };
          })
        ]
        ++ map (service: {
          ${service} = {
            after = [ "postgresql-contract-ownership.service" ];
            requires = [ "postgresql-contract-ownership.service" ];
          };
        }) ownershipConsumers
      );
    })
  ];
}
