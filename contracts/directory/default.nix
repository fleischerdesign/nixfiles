# contracts/directory/default.nix
# The identity directory's structure, declared once for the whole fleet.
#
# Three components need these values and none of them may restate them: the provider that
# serves the directory, the outpost that exposes it, and every consumer that authenticates
# against it. The values are properties of the directory, not of a host or a service, so they
# live in a contract module - it is loaded on every host (lib/core/module-loader.nix) and is
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

  config.my.directory.ldap = {
    baseDn = lib.mkDefault "DC=vyrx,DC=de";
    usersDn = "${config.my.directory.ldap.usersOu},${config.my.directory.ldap.baseDn}";
    groupsDn = "${config.my.directory.ldap.groupsOu},${config.my.directory.ldap.baseDn}";
  };
}
