{ pkgs, lib, ... }:
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
then
  pkgs.runCommandLocal "publications-contract-check" { } ''
    echo "publication references, ingress coherence and five independent negative controls passed" > "$out"
  ''
else
  throw "publications contract fixture failed: expected a derived name and five distinct errors"
