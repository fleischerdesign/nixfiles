{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Two users where the alphabetical first (alice) is NOT the primary (zoe): if the module
  # still picked by traversal order, fullName would say Alice. The fixture directory - not the
  # repository's user/ - proves discovery reads `usersDir`: philipp must be absent.
  evalUsers =
    primary:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
        usersDir = ./fixtures/users;
        usersLib = import ../lib/users.nix { inherit lib; };
      };
      modules = [
        ../features/system/user/nixos.nix
        {
          options.networking.hostName = lib.mkOption {
            type = lib.types.str;
            default = "fixture";
          };
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
          options.users.users = lib.mkOption {
            type = lib.types.attrsOf lib.types.attrs;
            default = { };
          };
          options.sops.secrets = lib.mkOption {
            type = lib.types.attrsOf lib.types.attrs;
            default = { };
          };
          options.users.groups = lib.mkOption {
            type = lib.types.attrsOf lib.types.attrs;
            default = { };
          };
          options.systemd.tmpfiles.rules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          options.environment.sessionVariables = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
          config.my.user.primary = primary;
          # The SOPS-derived password default is a production wiring concern, not part of this
          # fixture: pin it so the secret path is never read here.
          config.my.user.hashedPasswordFile = null;
        }
      ];
    }).config;

  valid = evalUsers "zoe";
  checksPassed =
    valid.my.user.primary == "zoe"
    && valid.my.user.fullName == "Zoe Example"
    && valid.users.users.alice.description == "Alice Example"
    && valid.users.users.zoe.description == "Zoe Example"
    && !(valid.users.users ? philipp)
    && lib.any (lib.hasInfix "d /home/alice ") valid.systemd.tmpfiles.rules
    && lib.any (lib.hasInfix "d /home/zoe ") valid.systemd.tmpfiles.rules
    && valid.my.user.usersDir == ./fixtures/users;

  # An unknown primary must fail loudly instead of becoming somebody else. Assertions evaluate
  # to false rather than throwing, so the control converts a false verdict into a throw.
  unknownPrimary = builtins.tryEval (
    if lib.all (a: a.assertion) (evalUsers "mallory").assertions then
      true
    else
      throw "unknown primary 'mallory' was accepted"
  );

  mkComposedHost =
    homeUsers:
    (import ../lib/mk-system.nix {
      home-manager-unstable = inputs.home-manager-unstable;
    }).mkSystem
      {
        hostname = "hom-wrk-01";
        inherit inputs pkgs homeUsers;
        usersDir = ./fixtures/users;
        globalModules = [
          inputs.sops-nix.nixosModules.sops
          inputs.nod.nixosModules.default
        ];
        extraModules = [
          ({ lib, ... }: {
            my.user.primary = lib.mkForce "zoe";
            my.user.hashedPasswordFile = lib.mkForce null;
          })
        ];
      };

  assignedHost = mkComposedHost [ { name = "zoe"; } ];
  unassignedHost = mkComposedHost [ ];
  duplicateAssignment = builtins.tryEval (
    builtins.attrNames
      (mkComposedHost [
        { name = "zoe"; }
        { name = "zoe"; }
      ]).config.home-manager.users
  );
  composedUsersPass =
    builtins.attrNames assignedHost.config.home-manager.users == [ "zoe" ]
    && builtins.attrNames unassignedHost.config.home-manager.users == [ ]
    && assignedHost.config.users.users ? alice
    && assignedHost.config.users.users ? zoe
    && !duplicateAssignment.success;
in
if checksPassed && !unknownPrimary.success && composedUsersPass then
  pkgs.runCommandLocal "users-check" { } ''
    echo "shared identity source, explicit Home Manager selection, duplicate rejection and primary-user checks passed" > "$out"
  ''
else
  throw "users fixture failed: expected shared-source accounts, explicit Home Manager assignments and loud ambiguity/unknown-primary rejection"
