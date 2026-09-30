# OIDC and LDAP integrations refer to a publication, not the listener that implements it.
{ lib }:
{
  oidc =
    service:
    lib.types.submodule (submod: {
      options = {
        publication = lib.mkOption {
          type = lib.types.str;
          description = "Publication id supplying the application's public name and redirects.";
        };
        enable = lib.mkEnableOption "Expose publication as Authentik OIDC Application";

        clientId = lib.mkOption {
          type = lib.types.str;
          default = submod.config._module.args.name or "app";
          description = "OIDC Client ID (defaults to the integration's attribute name)";
        };

        clientSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Plaintext client secret (discouraged in favor of clientSecretEnv or secretPath)";
        };

        clientSecretEnv = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Environment variable name containing the client secret (e.g. AUTHENTIK_OIDC_SECRET_...)";
        };

        secretPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "SOPS secret path containing the client secret (e.g. 'services/apps/paperless_oidc_secret')";
        };

        redirectPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Relative redirect callback paths (e.g. [ '/api/auth/callback' ])";
        };

        redirectUris = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Explicit redirect URIs. If empty, synthesized from the publication's canonical and additional/alias domains plus redirectPaths.";
        };

        subMode = lib.mkOption {
          type = lib.types.enum [
            "hashed_user_id"
            "user_username"
            "user_email"
            "user_upn"
          ];
          default = "hashed_user_id";
          description = "Subject mode identifier mapping";
        };

        includeClaimsInIdToken = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to include user claims directly in the ID token";
        };

        grantTypes = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "authorization_code"
              "implicit"
              "hybrid"
              "refresh_token"
              "client_credentials"
              "password"
              "device_code"
            ]
          );
          default = [
            "authorization_code"
            "refresh_token"
          ];
          description = "Allowed OAuth2 grant types for the provider";
        };

        signingKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "authentik Internal JWT Certificate";
          description = "Name of the certificate/keypair in Authentik used to sign ID and access tokens for JWKS";
        };

        propertyMappings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "openid"
            "email"
            "profile"
          ];
          description = "Authentik scope mappings attached to the provider to populate scopes and claims (e.g. openid, email, profile)";
        };

        accessTokenValidity = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Authentik access token lifetime; null preserves the provider default.";
        };

        scopeMappings = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                scopeName = lib.mkOption { type = lib.types.str; };
                expression = lib.mkOption { type = lib.types.lines; };
              };
            }
          );
          default = { };
          description = "Application-specific OIDC scope mappings compiled alongside the provider.";
        };
      };
      config = {
        redirectUris =
          let
            epConfig =
              service.publications.${submod.config.publication} or {
                canonicalDomain = null;
                extraDomains = [ ];
              };
            allDomains =
              (lib.optional (epConfig.canonicalDomain != null) epConfig.canonicalDomain) ++ epConfig.extraDomains;
          in
          lib.mkDefault (
            lib.concatMap (dom: map (path: "https://${dom}${path}") submod.config.redirectPaths) allDomains
          );
      };
    });
  ldap =
    service:
    lib.types.submodule (submod: {
      options = {
        publication = lib.mkOption {
          type = lib.types.str;
          description = "Publication id whose audience authenticates through this directory.";
        };
        enable = lib.mkEnableOption "Authenticate this publication's users against the Authentik LDAP directory";

        accessGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default =
            (service.publications.${submod.config.publication} or { accessGroups = [ ]; }).accessGroups;
          description = "Inherited from the publication's `accessGroups`; the directory filter is a projection of it.";
        };

        adminGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = (service.publications.${submod.config.publication} or { adminGroups = [ ]; }).adminGroups;
          description = "Inherited from the publication's `adminGroups`.";
        };

        baseDn = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Directory base DN; null uses the one the LDAP provider declares.";
        };

        secretPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            SOPS path holding the app password this service binds with. An LDAP bind takes a username
            and a password, so this is an app password and not an API token, which authenticates to the
            HTTP API only. Null derives `services/authentik/consumers/<endpoint-name>-ldap-password`.
          '';
        };
      };
    });
}
