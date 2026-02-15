# lib/helper.nix
# Utility functions for NixOS and Home Manager configurations.
{ pkgs, home-manager-unstable, ... }:

let
  lib = pkgs.lib;

  # Recursively find all default.nix files in a directory
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

  # Main System Builder
  mkSystem = {
    system,
    pkgs, # Fertige Instanz aus flake.nix
    hostname,
    inputs,
    users ? [],
    extraModules ? []
  }:
  let
    featuresDir = ../features;
    userDir = ../user;
    
    # Automatically discover all feature modules
    allFeatureModules = findModules featuresDir;

    homeManagerUsers = lib.listToAttrs (map (user: {
      name = user.name;
      value = {
        imports =
          [ (import (userDir + "/${user.name}/home.nix")) ]
          ++ (user.homeModules or []);
      };
    }) users);

  in
  # WICHTIG: nixosSystem muss vom Input kommen, nicht von der pkgs-Instanz
  inputs.nixpkgs-unstable.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs hostname; };
    modules = [
      # Verwende die fertige pkgs Instanz
      { nixpkgs.pkgs = pkgs; }
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