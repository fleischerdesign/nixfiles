# contracts/dependencies/default.nix
# Declarative Dependency & Consumption Contract Specification (Inversion of Control).
# Services declare what external capabilities/databases/caches they require ('consumes')
# rather than database/cache providers having to hardcode consumer lists ('provides').
{
  config,
  lib,
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

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "PostgreSQL extensions required by the service (e.g. [ 'vector' 'uuid-ossp' ])";
      };
    };
  });

  # Redis consumer specification
  redisConsumerSubmodule = lib.types.submodule {
    options = {
      instance = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Redis instance or database identifier";
      };

      dbIndex = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Dedicated Redis DB index (0-15)";
      };
    };
  };

  # Directory (Authentik LDAP) consumer specification. A service that authenticates its
  # users against the directory declares *who may use it* and *who administers it*. The
  # policy therefore lives with the service it applies to, not in the directory: the
  # provider exposes identities, the consumer decides what they may do.
  ldapConsumerSubmodule = lib.types.submodule {
    options = {
      accessGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Authentik groups whose members may sign in to this service";
      };

      adminGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Groups whose members are administrators of this service (usually a subset of accessGroups)";
      };
    };
  };

  consumerContractSubmodule = lib.types.submodule {
    options = {
      postgresql = lib.mkOption {
        type = lib.types.attrsOf postgresConsumerSubmodule;
        default = { };
        description = "PostgreSQL databases required by this service";
      };

      redis = lib.mkOption {
        type = lib.types.attrsOf redisConsumerSubmodule;
        default = { };
        description = "Redis instances/databases required by this service";
      };

      ldap = lib.mkOption {
        type = lib.types.nullOr ldapConsumerSubmodule;
        default = null;
        description = ''
          Directory this service authenticates against. Setting it does not grant access -
          it states which identities the service accepts, and is projected into the
          service's own client configuration. `accessGroups` is required, because a service
          that authenticates against the directory without saying who may use it has no policy.
        '';
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
in
{
  options.my.contracts.consumes = lib.mkOption {
    type = lib.types.attrsOf consumerContractSubmodule;
    default = { };
    description = "Service-level inbound dependencies (Databases, Caches, Brokers) requested by local features";
  };

  # Inversion of Control Projection:
  # When PostgreSQL is enabled locally on this host, automatically provision
  # all databases and users declared by consumers on this host!
  config = lib.mkIf (config.services.postgresql.enable or false) {
    services.postgresql = {
      ensureDatabases = uniqueDatabases;
      ensureUsers = uniqueUsers;
    };
  };
}
