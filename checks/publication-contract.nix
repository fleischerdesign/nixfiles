{
  pkgs,
  lib,
  self,
  ...
}:
let
  fixture =
    values:
    (lib.evalModules {
      modules = [
        {
          options.assertions = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  assertion = lib.mkOption { type = lib.types.bool; };
                  message = lib.mkOption { type = lib.types.str; };
                };
              }
            );
            default = [ ];
          };
          options.my.topology.domain = lib.mkOption {
            type = lib.types.str;
            default = "example.test";
          };
          options.my.contracts.provides = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.endpoints = lib.mkOption {
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options = {
                        port = lib.mkOption { type = lib.types.port; };
                        applicationProtocol = lib.mkOption { type = lib.types.str; };
                      };
                    }
                  );
                  default = { };
                };
              }
            );
          };
        }
        ../contracts/publications/nixos.nix
        { my.contracts.provides.example = values; }
      ];
    }).config;
  endpoints = {
    web = {
      port = 8080;
      applicationProtocol = "http";
    };
    ssh = {
      port = 2222;
      applicationProtocol = "ssh";
    };
  };
  failures =
    value: map (entry: entry.message) (lib.filter (entry: !entry.assertion) (fixture value).assertions);
  valid = {
    inherit endpoints;
    publications.web = {
      endpoint = "web";
      scope = "public";
      subdomain = "app";
    };
  };
  unknown = failures {
    inherit endpoints;
    publications.web = {
      endpoint = "missing";
      scope = "public";
      subdomain = "app";
    };
  };
  nameless = failures {
    inherit endpoints;
    publications.web = {
      endpoint = "web";
      scope = "isolated";
    };
  };
  wrongProtocol = failures {
    inherit endpoints;
    publications.ssh = {
      endpoint = "ssh";
      scope = "public";
      subdomain = "ssh";
    };
  };
  authWithoutIngress = failures {
    inherit endpoints;
    publications.web = {
      endpoint = "web";
      scope = "public";
      subdomain = "app";
      ingress = false;
      auth = "authentik";
      accessGroups = [ "members" ];
    };
  };
  duplicateName = failures {
    inherit endpoints;
    publications = {
      first = {
        endpoint = "web";
        scope = "public";
        subdomain = "app";
      };
      second = {
        endpoint = "web";
        scope = "public";
        subdomain = "app";
      };
    };
  };
  namingProjection = import ../contracts/naming/nixos.nix {
    inherit lib;
    config = {
      my.topology = {
        domain = "example.test";
        ingressHost = "node-a";
        devices = { };
        hosts.node-a = {
          ipv4 = "198.51.100.10";
          wireguardIpv4 = "192.0.2.10";
        };
      };
    };
    fleetConfigs = {
      systems = _: {
        node-a.config.my.contracts.provides.demo = {
          endpoints.web.directAccess.enable = false;
          publications.web = {
            endpoint = "web";
            scope = "public";
            canonicalDomain = "service.example.test";
            fqdn = null;
            extraDomains = [ "NODE-A.NODE.EXAMPLE.TEST" ];
            aliases = [ ];
            auth = "authentik";
            publicExempt = null;
          };
        };
      };
      providesOf = host: host.config.my.contracts.provides;
    };
  };
  nameCollision = lib.filter (assertion: !assertion.assertion) namingProjection.config.assertions;
  aliasHost = self.nixosConfigurations.hom-srv-01.extendModules {
    specialArgs.flake = fixtureFleet;
    modules = [
      {
        my.contracts.provides.audit-alias = {
          endpoints.web.port = 18999;
          publications.web = {
            endpoint = "web";
            scope = "public";
            subdomain = "audit-primary";
            auth = "oidc";
            accessGroups = [ "media-users" ];
            aliases = [ "audit-legacy.vyrx.de" ];
          };
          identity.oidc.browser = {
            enable = true;
            publication = "web";
            redirectPaths = [ "/callback" ];
          };
        };
        my.contracts.provides.audit-mesh = {
          endpoints.web.port = 18998;
          publications.web = {
            endpoint = "web";
            scope = "mesh";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "audit-mesh";
          };
        };
      }
    ];
  };
  authentikHost = self.nixosConfigurations.cld-edge-01.extendModules {
    specialArgs.flake = fixtureFleet;
  };
  fixtureFleet = self // {
    nixosConfigurations = self.nixosConfigurations // {
      hom-srv-01 = aliasHost;
      cld-edge-01 = authentikHost;
    };
  };
  aliasPublication = aliasHost.config.my.contracts.provides.audit-alias.publications.web;
  aliasRedirects =
    aliasHost.config.my.contracts.provides.audit-alias.identity.oidc.browser.redirectUris;
  aliasDnsAnswers = aliasHost.config.my.features.services.dns.answers;
  cloudflareRecords = authentikHost.config.my.features.system.networking.cloudflare.effectiveRecords;
  authentikBlueprints = authentikHost.config.my.features.services.authentik.server.blueprintsDir;
  blueprintRedirectCheck =
    pkgs.runCommandLocal "publication-authentik-redirect-check"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        grep -F 'https://audit-legacy.vyrx.de/callback' ${authentikBlueprints}/03-apps/oidc-apps-generated.yaml >/dev/null
        grep -F 'https://audit-mesh.mesh.vyrx.de' ${authentikBlueprints}/03-apps/proxy-apps-generated.yaml >/dev/null
        touch "$out"
      '';
  contains = text: strings: lib.any (lib.hasInfix text) strings;
in
if
  failures valid == [ ]
  &&
    (fixture valid).my.contracts.provides.example.publications.web.canonicalDomain == "app.example.test"
  && (fixture valid).my.contracts.provides.example.publications.web.port == 8080
  && contains "unknown endpoint 'missing'" unknown
  && contains "yields no DNS name" nameless
  && contains "ingress terminates HTTP" wrongProtocol
  && contains "enforced by the ingress" authWithoutIngress
  && contains "one endpoint, one name" duplicateName
  && lib.any (assertion: lib.hasInfix "Naming I2" assertion.message) nameCollision
  && builtins.elem "audit-legacy.vyrx.de" aliasPublication.extraDomains
  && aliasHost.config.services.caddy.virtualHosts ? "audit-legacy.vyrx.de"
  && aliasHost.config.services.caddy.virtualHosts ? "audit-mesh.mesh.vyrx.de"
  && authentikHost.config.services.caddy.virtualHosts ? "audit-legacy.vyrx.de"
  && builtins.elem "https://audit-legacy.vyrx.de/callback" aliasRedirects
  && lib.any (answer: answer.name == "audit-legacy.vyrx.de." && answer.plane == "lan") aliasDnsAnswers
  && lib.any (record: record.name == "audit-legacy.vyrx.de") cloudflareRecords
then
  pkgs.runCommandLocal "publications-contract-check" { } ''
    test -e ${blueprintRedirectCheck}
    echo "publication references, DNS/Cloudflare/Caddy/Authentik projections, ingress coherence, namespace collisions and negative controls passed" > "$out"
  ''
else
  throw "publication contract fixture failed: expected derived names, coherent ingress and fleet-wide name ownership"
