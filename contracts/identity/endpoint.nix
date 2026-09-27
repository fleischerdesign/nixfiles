# Audience declarations of a publication; listener address and DNS remain elsewhere.
{ lib, submod }:
let
  audience = import ./lib/audience.nix;
in
{
  options = {
    # Who may use this publication. One declaration per service, projected three ways: the ingress gate
    # (an Authentik policy binding on the application for `auth = "authentik"` or `"oidc"`), the
    # directory filter (an LDAP consumer's memberOf), and the portal (vyrx.de shows a user only what
    # these groups allow). Deliberately no default: a service published through the ingress without
    # naming its audience has no policy, and the compiler refuses to build it.
    accessGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      # `apply` is the desugaring, and it is one line on purpose: `accessUsers` is a spelling of an
      # audience, not a second audience. The ingress binding, the directory filter and the portal all
      # read `accessGroups`, so none of them can miss the derived groups - which is the failure a
      # second field would have produced: an LDAP filter naming no group locks everyone out while the
      # deploy stays green.
      apply = groups: groups ++ map audience.audienceGroup submod.config.accessUsers;
      description = "Authentik groups whose members may use this publication, plus one group per declared `accessUsers`.";
    };

    # An audience named by people instead of by role. Each username becomes its own group
    # (`contracts/identity/lib/audience.nix`) and the compiler declares its membership, so this is the
    # same mechanism as a role group - only with one member, and declared.
    accessUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Usernames that may use this endpoint, each through its own audience group.";
    };

    # A group this endpoint accepted before its audience became a declaration. An apply adds and
    # updates; it does not remove a binding that is no longer named, so retiring an audience takes a
    # declaration of its own - the tombstone - or the old binding keeps granting what the change was
    # meant to end (docs/identity.md §11.3).
    retiredAccessGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Groups this endpoint no longer accepts; each is tombstoned on apply.";
    };

    adminGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Groups whose members administer this publication (usually a subset of accessGroups).";
    };
  };
}
