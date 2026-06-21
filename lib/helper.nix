# lib/helper.nix
# Utility functions for NixOS and Home Manager configurations.
{
  pkgs,
  home-manager-unstable,
  ...
}: let
  inherit (pkgs) lib;
  userLib = import ./users.nix;

  findModules = dir: let
    entries = builtins.readDir dir;
    current =
      if lib.hasAttr "default.nix" entries
      then [(dir + "/default.nix")]
      else [];
    subdirs = lib.filterAttrs (_: v: v == "directory") entries;
    subModules = lib.concatMap (name: findModules (dir + "/${name}")) (builtins.attrNames subdirs);
  in
    current ++ subModules;

  mkSystem = {
    system,
    pkgs,
    hostname,
    inputs,
    flake ? null,
    users ? [],
    extraModules ? [],
    globalModules ? [],
  }: let
    featuresDir = ../features;
    userDir = ../user;

    allFeatureModules = findModules featuresDir;

    nixosUsers = lib.listToAttrs (
      map (user: {
        inherit (user) name;
        value = {
          isNormalUser = true;
          description = (userLib.${user.name} or {description = "User ${user.name}";}).description or "User ${user.name}";
          extraGroups =
            user.extraGroups or [
              "networkmanager"
              "wheel"
            ];
          openssh.authorizedKeys.keys = (userLib.${user.name} or {sshKeys = [];}).sshKeys or [];
        };
      })
      users
    );

    homeManagerUsers = lib.listToAttrs (
      map (user: {
        inherit (user) name;
        value = {
          imports = [(import (userDir + "/${user.name}/home.nix"))] ++ (user.homeModules or []);
        };
      })
      users
    );
  in
    inputs.nixpkgs-unstable.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs hostname flake;};
      modules =
        [
          {nixpkgs.pkgs = pkgs;}
          {users.users = nixosUsers;}
        ]
        ++ globalModules
        ++ extraModules
        ++ allFeatureModules
        ++ [
          ../hosts/${hostname}/configuration.nix
          home-manager-unstable.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = {inherit inputs hostname;};
              users = homeManagerUsers;
            };
          }
        ];
    };
in {
  inherit mkSystem;
}
