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
  # ATTR PATH GENERATION (with Context Stripping)
  # =========================================================================
  
  # Converts metadata to an attribute path.
  metadataToAttrPath = metadata:
    let
      # Remove .nix extension.
      pathWithoutNix = lib.removeSuffix ".nix" metadata.relPath;
      
      # Remove /default suffix.
      pathWithoutDefault = 
        if lib.hasSuffix "/default" pathWithoutNix
        then lib.removeSuffix "/default" pathWithoutNix
        else pathWithoutNix;
    in
    lib.splitString "/" pathWithoutDefault;

  # =========================================================================
  # OPTION GENERATION (Optimized with Metadata)
  # =========================================================================
  
  # Generates a single option from metadata.
  mkOptionFromMetadata = namespace: metadata:
    let
      attrPath = metadataToAttrPath metadata;
      fullPath = namespace ++ attrPath ++ ["enable"];
    in
    lib.setAttrByPath fullPath (lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable module '${lib.concatStringsSep "." (namespace ++ attrPath)}'";
    });
  
  # Batch generation of all options (using fold for performance).
  mkAllOptions = namespace: metadataList:
    lib.foldl' 
      (acc: meta: lib.recursiveUpdate acc (mkOptionFromMetadata namespace meta))
      {}
      metadataList;

  # =========================================================================
  # MODULE SYSTEM (Metadata-based)
  # =========================================================================
  
  mkModuleOptions = { baseDir, optionPath }:
    let
      metadata = getFileMetadata baseDir;
      options = mkAllOptions optionPath metadata;
    in
    { options = options; };
  
  mkModuleSet = { baseDir, optionPath }:
    let
      metadata = getFileMetadata baseDir;
      
      # Pass 2: Lazily import modules.
      modules = map (meta: import meta.path) metadata;
      
      optionsModule = mkModuleOptions { inherit baseDir optionPath; };
    in
    [ optionsModule ] ++ modules;

  # =========================================================================
  # HOME MANAGER USER CONFIG (Optimized)
  # =========================================================================
  
  mkHomeManagerUserConfig = homeManagerDir: user:
    let
      globalModulesDir = homeManagerDir + "/default";
      userModulesDir = homeManagerDir + "/${user.name}";
      
      # Metadata-based scans (no immediate import).
      globalMeta = getFileMetadata globalModulesDir;
      userMeta = getFileMetadata userModulesDir;
      
      # Load modules from metadata.
      globalModules = map (meta: import meta.path) globalMeta;
      
      # Generate user options.
      userOptions = mkAllOptions ["my" "homeManager"] userMeta;
      userOptionsModule = { options = userOptions; };
      
      # User-specific modules.
      userModules = map (meta: import meta.path) userMeta;
      
      # Check if user home.nix exists.
      userHomeConfig = 
        let homeFile = userModulesDir + "/home.nix";
        in if builtins.pathExists homeFile
           then [ (import homeFile) ]
           else [];
    in
    {
      name = user.name;
      value = {
        imports = 
          [ userOptionsModule ]
          ++ globalModules
          ++ userModules 
          ++ userHomeConfig
          ++ (user.homeModules or []);
      };
    };

  # =========================================================================
  # Main entry point for system configuration.
  mkSystem = {
    system,
    hostname,
    inputs,
    users ? [],
    overlays ? []
  }:
  let
    hostsDir = toString ../hosts;
    modulesDir = toString ../modules/nixos;
    homeManagerDir = toString ../home-manager;
    
    # Optimized user configuration generation.
    homeManagerUsers = lib.listToAttrs 
      (map (mkHomeManagerUserConfig homeManagerDir) users);
    
    # NixOS module set with metadata-based scan.
    nixosModuleSet = mkModuleSet { 
      baseDir = modulesDir; 
      optionPath = ["my" "nixos"]; 
    };
    
    # Host-specific configuration.
    hostConfig = hostsDir + "/${hostname}/configuration.nix";
  in
  pkgs-unstable.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      # Nixpkgs Config
      { nixpkgs = { inherit overlays; config.allowUnfree = true; }; }
      
      # Base Config
      (import (hostsDir + "/base.nix"))
    ] 
    ++ nixosModuleSet 
    ++ [
      # Host-spezifische Config
      (import hostConfig)
      
      # Home Manager Integration
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
  inherit mkModuleOptions mkModuleSet mkSystem;
  
  # Expose für Testing/Debugging
  inherit getFileMetadata metadataToAttrPath;
}
