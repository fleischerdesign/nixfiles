# lib/helper.nix
# Utility functions for NixOS and Home Manager configurations.
{ pkgs-unstable, home-manager-unstable, ... }:

let
  lib = pkgs-unstable.lib;

  # =========================================================================
  # SNOWFALL OPTIMIZATION 1: Context-Stripped Paths
  # =========================================================================
  # Strips string context for O(1) lookups instead of O(n).
  stripContext = str: builtins.unsafeDiscardStringContext str;

  # =========================================================================
  # SNOWFALL OPTIMIZATION 2: Smart Directory Scanning
  # =========================================================================
  
  # Safely read directory with a pathExists check.
  safeReadDir = dir:
    if builtins.pathExists dir
    then builtins.readDir dir
    else {};
  
  # Separates directories and files (Snowfall pattern).
  getDirEntries = dir:
    let
      entries = safeReadDir dir;
      dirs = lib.filterAttrs (n: v: v == "directory") entries;
      files = lib.filterAttrs (n: v: v == "regular") entries;
    in
    { inherit dirs files; };

  # =========================================================================
  # SNOWFALL OPTIMIZATION 3: Two-Pass Metadata Loading
  # =========================================================================
  
  # Pass 1: Collects metadata (lightweight, no import).
  getFileMetadata = baseDir:
    let
      scanDir = dir:
        let
          entries = getDirEntries dir;
          
          # Recursively scan subdirectories.
          subFiles = lib.concatMap 
            (name: scanDir (dir + "/${name}"))
            (builtins.attrNames entries.dirs);
          
          # Create metadata for all files in the current directory.
          currentFiles = lib.mapAttrsToList
            (name: _: 
              let
                fullPath = dir + "/${name}";
                # Strip context for performance.
                relPath = stripContext (
                  lib.removePrefix (toString baseDir + "/") (toString fullPath)
                );
              in {
                path = fullPath;
                name = stripContext name;
                inherit relPath;
              })
            entries.files;
        in
        currentFiles ++ subFiles;
      
      allFiles = scanDir baseDir;
      
      # Filter .nix files (excluding home.nix).
      nixFiles = builtins.filter 
        (f: lib.hasSuffix ".nix" f.name && f.name != "home.nix") 
        allFiles;
    in
    nixFiles;

  # =========================================================================
  # UNIFIED FEATURE SYSTEM
  # =========================================================================

  mkSystem = {
    system,
    hostname,
    inputs,
    users ? [],
    overlays ? [],
    extraModules ? []
  }:
  let
    hostsDir = ../hosts;
    rolesDir = ../roles;
    featuresDir = ../features;
    userDir = ../user;

    hostMetadata = import (hostsDir + "/${hostname}/metadata.nix");

    allFeatureFiles = getFileMetadata featuresDir;
    allFeatureModules = map (meta: import meta.path) allFeatureFiles;

    roleModule = import (rolesDir + "/${hostMetadata.role}.nix");

    # Dynamically build the `my.features` attribute set from metadata.
    # This allows `metadata.nix` to use simple booleans for most features,
    # but also attribute sets for features with more complex options.
    featureFlagsModule = {
      my.features = lib.mapAttrs
        (name: value:
          if lib.isAttrs value then value
          else { enable = value; }
        )
        hostMetadata.features;
    };

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
    specialArgs = { inherit inputs hostname; };
    modules = [
      # Base Nixpkgs config
      { nixpkgs = { inherit overlays; config.allowUnfree = true; }; }
    ]
    ++ extraModules
    ++ [
      roleModule
    ] ++ allFeatureModules ++ [
      featureFlagsModule
      (import (hostsDir + "/${hostname}/configuration.nix"))
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
  # Public API
  inherit mkSystem;
  
  # Expose for testing/debugging
  inherit getFileMetadata;
}
