# contracts/publications/nixos.nix
# A publication puts a name on a listener: its DNS identity, its exposure plane and, when the ingress
# terminates it, its HTTP policy and audience. The listener itself owns none of this.
{ config, lib, ... }:
let
  publication =
    service:
    lib.types.submodule (submod: {
      imports = [
        (import ../identity/publication.nix { inherit lib submod; })
        (import ../ingress/publication.nix { inherit lib; })
      ];
      options = {
        endpoint = lib.mkOption {
          type = lib.types.str;
          description = "Endpoint id this publication names.";
        };
        scope = lib.mkOption {
          type = lib.types.enum [
            "public"
            "internal"
            "mesh"
            "isolated"
          ];
          default = "internal";
          description = ''
            Exposure plane that decides the derived name: `public` publishes the bare zone,
            `internal` a `lan.` subdomain, `mesh` a `mesh.` subdomain, `isolated` no name at all.
          '';
        };
        domain = lib.mkOption {
          type = lib.types.str;
          default = config.my.topology.domain;
          description = "Apex zone for derived names. Naming never depends on the serving host.";
        };
        fqdn = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "vyrx.de";
          description = ''
            Explicit FQDN override (escape hatch). Only for names that cannot follow the plane
            scheme: the zone apex, or a foreign domain.
          '';
        };
        aliases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Legacy names published as aliases during a rename window.";
        };
        subdomain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Canonical subdomain prefix (e.g. 'jellyfin' -> jellyfin.vyrx.de), or @ for the apex.";
        };
        extraDomains = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          apply = domains: lib.unique (domains ++ submod.config.aliases);
          description = "Additional and legacy alias DNS names associated with this publication";
        };

        port = lib.mkOption {
          type = lib.types.port;
          readOnly = true;
          description = "Port of the referenced endpoint, resolved once for every consumer of the name.";
        };

        # Computed Read-Only Options
        planeSuffix = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "DNS suffix contributed by the exposure scope (null = no name).";
        };

        canonicalDomain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "The fully resolved FQDN of the service. Null if scope is isolated.";
        };

        publicUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "The public HTTPS URL of the service. Null if canonicalDomain is null.";
        };
      };

      config = {
        port = (service.endpoints.${submod.config.endpoint} or { port = 0; }).port;

        planeSuffix =
          if submod.config.scope == "public" then
            ""
          else if submod.config.scope == "internal" then
            "lan."
          else if submod.config.scope == "mesh" then
            "mesh."
          else
            null;

        canonicalDomain =
          if submod.config.fqdn != null then
            submod.config.fqdn
          else if submod.config.planeSuffix == null then
            null
          else if submod.config.subdomain == null || submod.config.subdomain == "" then
            null
          else if submod.config.subdomain == "@" then
            submod.config.domain
          else
            "${submod.config.subdomain}.${submod.config.planeSuffix}${submod.config.domain}";

        publicUrl =
          if submod.config.canonicalDomain != null then "https://${submod.config.canonicalDomain}" else null;
      };
    });

  invalid = lib.concatLists (
    lib.mapAttrsToList (
      service: contract:
      lib.concatLists (
        lib.mapAttrsToList (
          name: pub:
          let
            endpointExists = builtins.hasAttr pub.endpoint contract.endpoints;
            ep = if endpointExists then contract.endpoints.${pub.endpoint} else null;
          in
          lib.optional (!endpointExists) "${service}.publications.${name}: unknown endpoint '${pub.endpoint}'"
          ++ lib.optional (endpointExists && pub.canonicalDomain == null) (
            "${service}.publications.${name}: scope '${pub.scope}' yields no DNS name; "
            + "give it a subdomain, an fqdn, or drop the publication"
          )
          ++ lib.optional (endpointExists && pub.ingress && ep.applicationProtocol != "http") (
            "${service}.publications.${name}: the ingress terminates HTTP, but endpoint "
            + "'${pub.endpoint}' speaks '${ep.applicationProtocol}'"
          )
          ++ lib.optional (pub.auth != "none" && !pub.ingress) (
            "${service}.publications.${name}: auth '${pub.auth}' is enforced by the ingress, "
            + "which this publication disables"
          )
        ) contract.publications
      )
      ++ lib.concatLists (
        lib.mapAttrsToList
          (
            endpoint: pairs:
            let
              names = map (pair: pair.name) pairs;
            in
            lib.optional (builtins.length names > 1) (
              "${service}: endpoint '${endpoint}' has ${toString (builtins.length names)} named publications "
              + "(${lib.concatStringsSep ", " names}); one endpoint, one name - "
              + "consumers resolve a publication per endpoint without list order"
            )
          )
          (
            lib.groupBy (pair: pair.endpoint) (
              lib.filter (pair: pair.named) (
                lib.mapAttrsToList (name: pub: {
                  inherit name;
                  inherit (pub) endpoint;
                  named = pub.canonicalDomain != null;
                }) contract.publications
              )
            )
          )
      )
    ) config.my.contracts.provides
  );
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }: {
          options.publications = lib.mkOption {
            type = lib.types.attrsOf (publication config);
            default = { };
            description = "Named DNS and ingress faces of this service's endpoints.";
          };
        }
      )
    );
  };

  config.assertions = [
    {
      assertion = invalid == [ ];
      message = "invalid publications:\n${lib.concatStringsSep "\n" invalid}";
    }
  ];
}
