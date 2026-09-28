# Directory consumers are projected from the service's identity integrations.
{ config, lib, ... }:
let
  integrations = import ./integration.nix { inherit lib; };
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

      # Both of the following are resolved by the identity contract from the service's own
      # publication declaration; no consumer sets them, and none composes a DN. Compiling a consumer on the host it
      # runs on is what keeps this possible: neither value has to cross a host boundary.
      secretPath = lib.mkOption {
        type = lib.types.str;
        description = ''
          SOPS path of the app password this service binds with. The integration may name it explicitly,
          otherwise it derives `services/authentik/consumers/<service>-ldap-password`.
        '';
      };

      bindDn = lib.mkOption {
        type = lib.types.str;
        description = ''
          Distinguished name this service binds as, composed from the directory contract. The provider
          creates the account under the same name, so both sides agree while the consumer stays unaware
          of the directory's structure.
        '';
      };
    };
  };

  # Every enabled directory integration becomes a consumer with fully resolved values:
  # the audience it stated, the SOPS path its app password lives at, and the DN it binds as. The provider
  # that creates those accounts derives the same DN from the same directory contract, so both sides agree
  # without either reading the other's configuration - they do not even run on the same host, which is
  # exactly why this lives here and not in the provider's feature.
  ldapConsumers = builtins.foldl' (acc: svc: acc // ldapConsumerOf svc) { } (
    builtins.attrNames config.my.contracts.provides
  );

  # A service's directory consumer has one identity. Reject competing integrations rather than
  # choosing one by attribute order.
  ldapIntegrationsOf =
    service:
    lib.filterAttrs (_: ldap: ldap.enable) config.my.contracts.provides.${service}.identity.ldap;
  ambiguous = lib.filter (
    service: builtins.length (builtins.attrNames (ldapIntegrationsOf service)) > 1
  ) (builtins.attrNames config.my.contracts.provides);

  ambiguousOidc = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      let
        enabled = lib.filterAttrs (_: integration: integration.enable) contract.identity.oidc;
        publications = map (integration: integration.publication) (builtins.attrValues enabled);
        duplicates = lib.unique (
          lib.filter (
            publication: builtins.length (lib.filter (candidate: candidate == publication) publications) > 1
          ) publications
        );
      in
      map (
        publication: "${service}: multiple enabled OIDC integrations target publication '${publication}'"
      ) duplicates
    ) config.my.contracts.provides
  );

  ldapConsumerOf =
    svc:
    let
      ldapIntegrations = builtins.attrValues (ldapIntegrationsOf svc);
    in
    if ldapIntegrations == [ ] then
      { }
    else
      let
        integration = builtins.head ldapIntegrations;
        directory = config.my.directory.ldap;
      in
      {
        ${svc}.ldap = {
          inherit (integration) accessGroups adminGroups;
          secretPath =
            if integration.secretPath != null then
              integration.secretPath
            else
              "services/authentik/consumers/${svc}-ldap-password";
          bindDn = "cn=${directory.consumerAccountPrefix}${svc},${directory.usersDn}";
        };
      };

  invalidReferences = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      let
        check =
          kind: name: integration:
          lib.optional (
            !(builtins.hasAttr integration.publication contract.publications)
          ) "${service}.identity.${kind}.${name}: unknown publication '${integration.publication}'";
      in
      lib.concatLists (lib.mapAttrsToList (check "oidc") contract.identity.oidc)
      ++ lib.concatLists (lib.mapAttrsToList (check "ldap") contract.identity.ldap)
    ) config.my.contracts.provides
  );
  missingOidc = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      lib.concatLists (
        lib.mapAttrsToList (
          name: pub:
          lib.optional (
            pub.auth == "oidc"
            && !(lib.any (integration: integration.enable && integration.publication == name) (
              builtins.attrValues contract.identity.oidc
            ))
          ) "${service}.publications.${name}: OIDC ingress needs an enabled identity.oidc integration"
        ) contract.publications
      )
    ) config.my.contracts.provides
  );

in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }: {
          options.identity = {
            oidc = lib.mkOption {
              type = lib.types.attrsOf (integrations.oidc config);
              default = { };
              description = "Named OIDC integrations with the identity provider.";
            };
            ldap = lib.mkOption {
              type = lib.types.attrsOf (integrations.ldap config);
              default = { };
              description = "Named directory integrations for application authentication.";
            };
          };
        }
      )
    );
  };

  options.my.contracts.consumes = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
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
      }
    );
  };

  config = {
    my.contracts.consumes = ldapConsumers;
    assertions = [
      {
        assertion = ambiguous == [ ];
        message = "declare only one enabled directory integration per service: ${lib.concatStringsSep ", " ambiguous}";
      }
      {
        assertion = invalidReferences == [ ];
        message = "invalid identity integration references:\n${lib.concatStringsSep "\n" invalidReferences}";
      }
      {
        assertion = missingOidc == [ ];
        message = "missing identity integrations:\n${lib.concatStringsSep "\n" missingOidc}";
      }
      {
        assertion = ambiguousOidc == [ ];
        message = "ambiguous OIDC integrations:\n${lib.concatStringsSep "\n" ambiguousOidc}";
      }
    ];
  };
}
