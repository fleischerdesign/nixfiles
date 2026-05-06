# lib/helper.nix
# Utility functions for NixOS and Home Manager configurations.
{ pkgs, home-manager-unstable, ... }:

let
  lib = pkgs.lib;
  userLib = import ./users.nix;

  findModules = dir:
    let
      entries = builtins.readDir dir;
      current = if lib.hasAttr "default.nix" entries then
        [ (dir + "/default.nix") ]
      else
        [];
      subdirs = lib.filterAttrs (n: v: v == "directory") entries;
      subModules = lib.concatMap 
        (name: findModules (dir + "/${name}")) 
        (builtins.attrNames subdirs);
    in
    current ++ subModules;

  mkSystem = {
    system,
    pkgs,
    hostname,
    inputs,
    users ? [],
    extraModules ? []
  }:
  let
    featuresDir = ../features;
    userDir = ../user;
    
    allFeatureModules = findModules featuresDir;

    nixosUsers = lib.listToAttrs (map (user: {
      name = user.name;
      value = {
        isNormalUser = true;
        inherit (userLib.${user.name}) description;
        extraGroups = user.extraGroups or [ "networkmanager" "wheel" ];
        openssh.authorizedKeys.keys = userLib.${user.name}.sshKeys;
      };
    }) users);

    homeManagerUsers = lib.listToAttrs (map (user: {
      name = user.name;
      value = {
        imports =
          [ (import (userDir + "/${user.name}/home.nix")) ]
          ++ (user.homeModules or []);
      };
    }) users);

  in
  inputs.nixpkgs-unstable.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs hostname; };
    modules = [
      { nixpkgs.pkgs = pkgs; }
      { users.users = nixosUsers; }
      inputs.sops-nix.nixosModules.sops
    ]
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
          extraSpecialArgs = { inherit inputs hostname; };
          users = homeManagerUsers;
        };
      }
    ];
  };

in {
  inherit mkSystem;
}