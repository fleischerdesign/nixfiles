{ pkgs, lib, ... }:
let
  evaluate =
    declaration:
    (lib.evalModules {
      modules = [
        {
          options = {
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [ ];
            };
            my.topology.domain = lib.mkOption {
              type = lib.types.str;
              default = "example.test";
            };
          };
        }
        ../contracts/directory/nixos.nix
        { my.directory = declaration; }
      ];
    }).config;
  valid = evaluate {
    users = {
      seeded.initialProfile = {
        displayName = "Seeded";
        email = "initial@example.test";
      };
      invited = { };
    };
    groups = {
      ordinary = { };
      managed.members = [ "invited" ];
      empty.members = [ ];
      retired.state = "absent";
    };
  };
  passes = config: lib.all (check: check.assertion) config.assertions;
  invalid = declaration: !(passes (evaluate declaration));
  blueprint = import ../features/services/authentik/lib/blueprint.nix { inherit lib; };
  references = pkgs.writeText "directory-reference-fixtures.json" (
    builtins.toJSON {
      numeric = blueprint.refs.byField blueprint.models.user "username" "123";
      boolean = blueprint.refs.byField blueprint.models.user "username" "true";
      punctuation = blueprint.refs.byField blueprint.models.user "username" "comma, quote\" bracket]";
      literal = "@@YAML_TAG@@!File /not-a-reference";
      file = blueprint.refs.file "/fixture/path with spaces";
    }
  );
in
assert passes valid;
assert valid.my.directory.users.invited.initialProfile == null;
assert valid.my.directory.groups.ordinary.members == null;
assert valid.my.directory.groups.empty.members == [ ];
assert invalid { groups.managed.members = [ "missing" ]; };
assert invalid {
  users.person = { };
  groups.managed.members = [
    "person"
    "person"
  ];
};
assert invalid {
  groups.retired = {
    state = "absent";
    members = [ ];
  };
};
assert invalid { groups."invalid group" = { }; };
assert invalid { users."invalid,user" = { }; };
pkgs.runCommand "directory-check"
  { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ]; }
  ''
      set -euo pipefail
    python3 ${./directory-membership.py} ${../features/services/authentik/lib/membership.py} \
      ${../features/services/authentik/lib/render-blueprint.py} ${references} \
      ${../contracts/directory/lib/preflight.py} > "$out"
  ''
