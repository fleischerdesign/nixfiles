{ pkgs, lib, ... }:
let
  fixture =
    declaration:
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
          options.my.directory.ldap = lib.mkOption {
            type = lib.types.attrs;
            default = {
              consumerAccountPrefix = "app-";
              usersDn = "ou=users,dc=test";
            };
          };
          options.my.contracts.provides = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options.endpoints.web = lib.mkOption {
                  type = lib.types.attrs;
                  default = { };
                };
                options.publications = lib.mkOption {
                  type = lib.types.attrsOf lib.types.attrs;
                  default = { };
                };
              }
            );
          };
        }
        ../contracts/identity/nixos.nix
        { my.contracts.provides.example = declaration; }
      ];
    }).config;
  failures =
    value: map (check: check.message) (lib.filter (check: !check.assertion) (fixture value).assertions);
  endpoint = {
    port = 443;
  };
  publication = {
    endpoint = "web";
    canonicalDomain = "example.test";
    extraDomains = [ ];
    auth = "oidc";
    accessGroups = [ "members" ];
  };
  valid = {
    endpoints.web = endpoint;
    publications.web = publication;
    identity.oidc.login = {
      publication = "web";
      enable = true;
      redirectPaths = [ "/callback" ];
    };
    identity.ldap.directory = {
      publication = "web";
      enable = true;
    };
  };
  unknown = failures {
    endpoints.web = endpoint;
    publications.web = publication;
    identity.oidc.bad = {
      publication = "missing";
      enable = true;
    };
  };
  missing = failures {
    endpoints.web = endpoint;
    publications.web = publication;
  };
  ambiguous = failures {
    endpoints.web = endpoint;
    publications.web = publication // {
      auth = "none";
    };
    identity.ldap = {
      first = {
        publication = "web";
        enable = true;
      };
      second = {
        publication = "web";
        enable = true;
      };
    };
  };
  contains = text: messages: lib.any (lib.hasInfix text) messages;
in
if
  failures valid == [ ]
  &&
    (fixture valid).my.contracts.provides.example.identity.oidc.login.redirectUris == [
      "https://example.test/callback"
    ]
  && (fixture valid).my.contracts.consumes.example.ldap.accessGroups == [ "members" ]
  && contains "unknown publication 'missing'" unknown
  && contains "OIDC ingress needs an enabled" missing
  && contains "only one enabled directory integration per service" ambiguous
then
  pkgs.runCommandLocal "identity-contract-check" { } ''
    echo "identity references, derived redirects and negative controls passed" > "$out"
  ''
else
  throw "identity contract fixture failed: reference, OIDC or LDAP invariants not enforced"
