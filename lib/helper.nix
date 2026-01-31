# lib/helper.nix
# Utility functions for NixOS and Home Manager configurations.
{ pkgs-unstable, home-manager-unstable, ... }:

let
  lib = pkgs-unstable.lib;
  setAttrByPath = lib.attrsets.setAttrByPath; # Extracted early binding


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
      
      # Filter only default.nix files to be loaded as modules.
      nixFiles = builtins.filter (f: f.name == "default.nix") allFiles;
    in
    nixFiles;

  # New function to get all feature metadata
  getAllFeatureMetas = baseDir:
    let
      scanMetas = dir:
        let
          entries = getDirEntries dir;

          # Recursively scan subdirectories for metadata.nix files
          subMetas = lib.concatMap
            (name: scanMetas (dir + "/${name}"))
            (builtins.attrNames entries.dirs);

          # Check for metadata.nix in current directory
          currentMeta =
            if lib.hasAttr "metadata.nix" entries.files then
              let
                fullPath = dir + "/metadata.nix";
                # desktop/niri/metadata.nix -> "desktop.niri"
                featurePath = lib.replaceStrings [ "/metadata.nix" ] [ "" ]
                  (stripContext (lib.removePrefix (toString baseDir + "/") (toString fullPath)));
                featurePathDots = lib.replaceStrings [ "/" ] [ "." ] featurePath;
              in
              [{ name = featurePathDots; value = import fullPath; }]
            else
              [];
        in
        currentMeta ++ subMetas;

      allMetasList = scanMetas baseDir;
    in
    lib.listToAttrs allMetasList; # Convert list of { name = "...", value = ... } to attrset


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
    roleModule = import (rolesDir + "/${hostMetadata.role}.nix");
    role = hostMetadata.role;

    allFeatureFiles = getFileMetadata featuresDir;
    allFeatureModules = map (meta: import meta.path) allFeatureFiles;
    
    # Converts a nested feature attribute set (like from hostMetadata.features or feature metadata.features)
    # into a flat list of "feature.path" strings for features that are explicitly enabled or required.
    # e.g., { desktop.niri.enable = true; dev.containers.users = [ "philipp" ]; }
    # -> [ "desktop.niri" "dev.containers" ]
    getFeaturePathsFromAttrSet = featureAttrs:
      let
        collect = path: value:
          if builtins.isAttrs value && lib.hasAttr "enable" value && value.enable then
            [ (lib.concatStringsSep "." path) ]
          else if builtins.isAttrs value then
            lib.concatMap (name: collect (path ++ [name]) value.${name}) (lib.attrNames value)
          else
            []; # Ignore values that are not attribute sets or not enabled.
      in
      collect [] featureAttrs;

    # Get all feature metadata (description, features, conflicts)
    allFeatureMetas = getAllFeatureMetas featuresDir;

    # --- Auto-Enablement Logic ---
    # This function recursively resolves dependencies and checks for conflicts.
    # It takes the initial set of explicitly enabled features and a map of all metadata.
    # Returns a list of all feature paths that should be enabled.
    resolveFeatures = initialEnabledPaths:
      let
        # Convert initial list of strings to a set for faster lookups
        # This set will grow as dependencies are resolved.
        enabledSet = lib.listToAttrs (map (f: { name = f; value = true; }) initialEnabledPaths);

        # Recursive function to resolve dependencies
        # currentEnabledSet: The set of features currently enabled.
        # queue: Features whose dependencies still need to be processed.
        recursiveResolve = currentEnabledSet: queue:
          if queue == [] then
            currentEnabledSet
          else
            let
              featureName = lib.head queue;
              remainingQueue = lib.tail queue;
              meta = allFeatureMetas.${featureName} or {};

              # Features required by the current feature
              requiredFeaturesMap = meta.features or {}; # Using 'features' key now
              requiredFeaturePaths = getFeaturePathsFromAttrSet requiredFeaturesMap;

              # Features conflicting with the current feature
              conflictingFeaturesMap = meta.conflicts or {};
              conflictingFeaturePaths = getFeaturePathsFromAttrSet conflictingFeaturesMap;

              # --- Conflict Check ---
              foundConflicts = lib.filter (con: lib.hasAttr con currentEnabledSet) conflictingFeaturePaths;
              _assertionConflicts =
                if foundConflicts != [] then
                  throw "Feature configuration error: Feature '${featureName}' conflicts with enabled feature(s): ${lib.concatStringsSep ", " foundConflicts}."
                else null; # Null so it compiles to nothing.

              # Identify new required features that are not yet enabled
              newlyRequired = lib.filter (req: !(lib.hasAttr req currentEnabledSet)) requiredFeaturePaths;

              # Merge new required features into the current set
              nextEnabledSet = lib.listToAttrs (lib.map (f: { name = f; value = true; }) newlyRequired) // currentEnabledSet;

              # Add new required features to the list of features to process
              nextQueue = remainingQueue ++ newlyRequired;
            in
            recursiveResolve nextEnabledSet nextQueue;
      in
      lib.attrsets.attrNames (recursiveResolve enabledSet initialEnabledPaths);

    # Get the set of features explicitly enabled by the host (and implicitly by role via hostMetadata)
    initialEnabledFromHost = getFeaturePathsFromAttrSet hostMetadata.features;

    # Resolve all dependencies and get the final list of enabled feature paths
    finalEnabledFeaturePaths = resolveFeatures initialEnabledFromHost;

    # Create a module that sets 'enable = true' for all finally enabled features
    # Function to convert "desktop.niri" to { desktop = { niri = { enable = true; } }; }
    createNestedEnabledAttr = featurePath:
      let
        pathSegments = lib.splitString "." featurePath;
        # Recursive helper to build the nested attribute set
        build = segments:
          if segments == [] then
            { enable = true; }
          else
            { "${lib.head segments}" = build (lib.tail segments); };
      in
      build pathSegments;

    finalFeatureFlagsModule = {
      my.features = lib.foldl (acc: featurePath:
        lib.recursiveUpdate acc (createNestedEnabledAttr featurePath)
      ) {} finalEnabledFeaturePaths;
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
    specialArgs = { inherit inputs hostname role; };
    modules = [
      # Base Nixpkgs config
      { nixpkgs = { inherit overlays; config.allowUnfree = true; }; }
      inputs.sops-nix.nixosModules.sops
    ]
    ++ extraModules
    ++ [ roleModule ] # roleModule must be present to define config.my.features defaults
    ++ allFeatureModules
    ++ [
      finalFeatureFlagsModule # Use the auto-enabled flags
      (import (hostsDir + "/${hostname}/configuration.nix"))
      home-manager-unstable.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = { inherit inputs hostname role; };
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
