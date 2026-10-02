# contracts/directory/nixos.nix
# The identity directory's structure, declared once for the whole fleet.
#
# Three components need these values and none of them may restate them: the provider that
# serves the directory, the outpost that exposes it, and every consumer that authenticates
# against it. The values are properties of the directory, not of a host or a service, so they
# live in a contract module - it is loaded on every host (lib/discovery.nix) and is
# deliberately not gated behind an enable flag, the same way the topology contract is.
#
# Derived values are read-only projections, not options a host may set:
#   usersDn / groupsDn   the two subtree DNs a consumer needs for its search base and filters
#   consumerBindDn       the bind DN per consumer service account, projected by the provider
#
# The rule that names those accounts belongs to the side that creates them, which is the
# provider: it composes the DN from its own account naming and projects the result. A consumer
# reads its entry and never composes a DN itself.
{
  config,
  lib,
  ...
}:
{
  options.my.directory.ldap = {
    baseDn = lib.mkOption {
      type = lib.types.str;
      description = "Directory root, e.g. DC=example,DC=org.";
      example = "DC=vyrx,DC=de";
    };

    usersOu = lib.mkOption {
      type = lib.types.str;
      default = "ou=users";
      description = "Relative DN of the subtree holding user entries.";
    };

    groupsOu = lib.mkOption {
      type = lib.types.str;
      default = "ou=groups";
      description = "Relative DN of the subtree holding group entries.";
    };

    usersDn = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Absolute DN of the users subtree: `<usersOu>,<baseDn>`.";
    };

    groupsDn = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Absolute DN of the groups subtree: `<groupsOu>,<baseDn>`.";
    };

    consumerAccountPrefix = lib.mkOption {
      type = lib.types.str;
      default = "ak-ldap-";
      description = ''
        Common-name prefix of a consumer service account. Both the provider, which creates the
        account, and the consumer, which binds with it, compose the DN from this value together
        with `usersDn`. The rule that names an account therefore exists once, and neither side has
        to read the other's configuration - which matters because provider and consumer usually
        live on different hosts.
      '';
    };
  };

  options.my.directory.users = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          initialProfile = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.submodule {
                options = {
                  displayName = lib.mkOption {
                    type = lib.types.str;
                    description = "Initial display name; subsequent changes belong to the person.";
                  };
                  email = lib.mkOption {
                    type = lib.types.str;
                    description = "Initial email address; subsequent changes belong to the person.";
                  };
                };
              }
            );
            default = null;
            description = "Create a missing account with these initial values only. Null references an existing UI-created account without creating or updating it.";
          };
        };
      }
    );
    default = { };
    description = "Human directory identities referenced by infrastructure, keyed by stable login name. This is not an exhaustive list of UI-created users or a Linux account inventory.";
  };

  options.my.directory.groups = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Purpose of this directory group.";
          };
          members = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = "Null leaves membership UI-owned; a list declares the exact usernames, including an explicitly empty group. Other groups on each user are untouched.";
          };
          state = lib.mkOption {
            type = lib.types.enum [
              "present"
              "absent"
            ];
            default = "present";
            description = "Desired group existence. Removal requires an explicit absent declaration, not merely deleting its inventory entry.";
          };
        };
      }
    );
    default = { };
    description = "Repository-owned directory group definitions, with explicit per-group membership ownership.";
  };

  config.assertions = [
    {
      assertion = lib.all (name: builtins.match "[A-Za-z0-9][A-Za-z0-9._@+-]*" name != null) (
        lib.attrNames config.my.directory.users
      );
      message = "Directory infrastructure usernames must be stable, non-empty login identifiers without whitespace or YAML delimiters.";
    }
    {
      assertion = lib.all (name: builtins.match "[a-z][a-z0-9-]*" name != null) (
        lib.attrNames config.my.directory.groups
      );
      message = "Directory role group names must be lowercase hyphenated identifiers.";
    }
    {
      assertion = lib.all (
        group:
        group.members == null
        || (
          group.state == "present"
          && lib.length group.members == lib.length (lib.unique group.members)
          && lib.all (name: lib.hasAttr name config.my.directory.users) group.members
        )
      ) (lib.attrValues config.my.directory.groups);
      message = "Directory managed membership must contain unique declared human identities and may only belong to a present group.";
    }
  ];

  config.my.directory.ldap = {
    # The DN is a projection of the topology's apex domain, never a second place that names it:
    # a literal here would keep serving the old directory after a domain move.
    baseDn = lib.mkDefault (
      "DC=" + lib.concatStringsSep ",DC=" (lib.splitString "." config.my.topology.domain)
    );
    usersDn = "${config.my.directory.ldap.usersOu},${config.my.directory.ldap.baseDn}";
    groupsDn = "${config.my.directory.ldap.groupsOu},${config.my.directory.ldap.baseDn}";
  };
}
