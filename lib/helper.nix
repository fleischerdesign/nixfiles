# lib/helper.nix
# Utility functions for NixOS and Home Manager configurations.
{ pkgs-unstable, home-manager-unstable, ... }:

let
  lib = pkgs-unstable.lib;

  # Recursively find all default.nix files in a directory
  # Returns a list of paths.
  findModules = dir:
    let
      entries = builtins.readDir dir;
      
      # If default.nix exists in current dir, return it (and don't recurse deeper for modules, 
      # assuming a folder with default.nix IS the module)
      current = if lib.hasAttr "default.nix" entries then
        [ (dir + "/default.nix") ]
      else
        [];
      
      # Recurse into directories
      subdirs = lib.filterAttrs (n: v: v == "directory") entries;
      subModules = lib.concatMap 
        (name: findModules (dir + "/${name}")) 
        (builtins.attrNames subdirs);
    in
    current ++ subModules;

  # Main System Builder
  mkSystem = {
    system,
    hostname,
    inputs,
    users ? [],
    overlays ? [],
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
  pkgs-unstable.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs hostname; }; # 'role' is no longer specialArg, it's imported in config
    modules = [
      # Base Nixpkgs config
      { nixpkgs = { inherit overlays; config.allowUnfree = true; }; }
      inputs.sops-nix.nixosModules.sops
    ]
    ++ extraModules
    ++ allFeatureModules
    ++ [
      (import (../hosts + "/${hostname}/configuration.nix"))
      home-manager-unstable.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = { inherit inputs hostname; };
          users = homeManagerUsers;
        };
      }
    ];
  };

in {
  inherit mkSystem;
}