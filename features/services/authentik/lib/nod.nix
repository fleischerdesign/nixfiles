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

  oauth2Provider =
    {
      name,
      clientId,
      redirectUris,
      authorizationFlow ? "default-provider-authorization-implicit-consent",
      invalidationFlow ? "default-provider-invalidation-flow",
      subMode ? "hashed_user_id",
      includeClaimsInIdToken ? true,
      grantTypes ? [
        "authorization_code"
        "refresh_token"
      ],
      accessTokenValidity ? null,
      propertyMappings ? [
        "openid"
        "email"
        "profile"
      ],
      clientSecretEnv ? null,
    }:
    nod.resource "authentik.provider.oauth2" name (
      {
        client_id = clientId;
        authorization_flow = authorizationFlow;
        invalidation_flow = invalidationFlow;
        redirect_uris = redirectUris;
        sub_mode = subMode;
        include_claims_in_id_token = includeClaimsInIdToken;
        grant_types = grantTypes;
        # Sorted, because the provider observes the resolved set in that order:
        # an unsorted declaration would report drift against itself.
        property_mappings = lib.sort (a: b: a < b) propertyMappings;
      }
      // lib.optionalAttrs (accessTokenValidity != null) {
        access_token_validity = accessTokenValidity;
      }
      # Names the variable, never the value. It is declared but not compared: a
      # create needs it, an observation can never echo it (ADR-043).
      // lib.optionalAttrs (clientSecretEnv != null) {
        client_secret_env = clientSecretEnv;
      }
    );

  # One document, with the duplicate check from the generic layer.
  desired = nod.desired;

  # The generic constructor, for tombstones that need the raw shape.
  inherit (nod) resource;
}
