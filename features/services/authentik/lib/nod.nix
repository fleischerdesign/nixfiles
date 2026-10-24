# The Authentik kinds a nod declaration can carry.
#
# Constructors, not hand-written attribute sets: a wrong field name or an
# unknown provider mode is an evaluation error, not a reconcile surprise.
{ lib, nodLib }:
let
  nod = nodLib;
in
rec {
  group =
    {
      name,
      description ? "",
      users ? null,
      isSuperuser ? false,
    }:
    nod.resource "authentik.group" name (
      {
        is_superuser = isSuperuser;
        inherit description;
      }
      // lib.optionalAttrs (users != null) { inherit users; }
    );

  user =
    {
      username,
      name,
      email,
    }:
    nod.resource "authentik.user" username { inherit name email; };

  application =
    {
      slug,
      name,
      provider ? "",
      launchUrl ? "",
      group ? "Services",
      accessGroups ? [ ],
      openInNewTab ? true,
    }:
    nod.resource "authentik.application" slug {
      inherit name provider;
      open_in_new_tab = openInNewTab;
      meta_launch_url = launchUrl;
      inherit group;
      access_groups = lib.sort (a: b: a < b) accessGroups;
    };

  proxyProvider =
    {
      name,
      externalHost,
      mode ? "forward_single",
      cookieDomain ? "",
      authorizationFlow ? "default-provider-authorization-implicit-consent",
      invalidationFlow ? "default-provider-invalidation-flow",
    }:
    assert lib.elem mode [
      "forward_single"
      "forward_domain"
    ];
    nod.resource "authentik.provider.proxy" name {
      inherit mode;
      external_host = externalHost;
      cookie_domain = cookieDomain;
      authorization_flow = authorizationFlow;
      invalidation_flow = invalidationFlow;
    };

  outpost =
    {
      name,
      providers,
      type ? "proxy",
      config,
    }:
    nod.resource "authentik.outpost" name { inherit type providers config; };

  # One document, with the duplicate check from the generic layer.
  desired = nod.desired;

  # The generic constructor, for tombstones that need the raw shape.
  inherit (nod) resource;
}
