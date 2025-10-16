# lib/helper.nix
{ pkgs-unstable, home-manager-unstable, ... }:

let
  lib = pkgs-unstable.lib; 

  getNixFilesRecursive = dir:
    let
      entries = builtins.readDir dir;
      processEntry = name: type:
        let path = dir + "/${name}"; in
        if type == "directory" then
          getNixFilesRecursive path
        else if type == "regular"
             && lib.hasSuffix ".nix" name
             && name != "home.nix" then
          [ path ]
        else [];
    in lib.flatten (lib.mapAttrsToList processEntry entries);
  
  pathToAttrPath = baseDir: filePath:
    let
      relativePath = lib.removePrefix (toString baseDir + "/") (toString filePath);
      pathWithoutNix = lib.removeSuffix ".nix" relativePath;
      pathWithoutDefault = if lib.hasSuffix "/default" pathWithoutNix
                         then lib.removeSuffix "/default" pathWithoutNix
                         else pathWithoutNix;
    in
    lib.splitString "/" pathWithoutDefault;
  
  buildOptionTree = paths:
    lib.foldl' (acc: path:
      let
        head = lib.head path;
        tail = lib.tail path;
        newVal = if tail == []
          then { enable = lib.mkOption {
                 type = lib.types.bool;
                 default = false;
                 description = "Enable module '${lib.concatStringsSep "." path}'";
               }; }
          else buildOptionTree [tail];
      in
        acc // { ${head} = (acc.${head} or {}) // newVal; }
    ) {} paths;

  mkModuleSet = { baseDir, optionPath ? [ "my" "modules" ] }:
    let
      files = getNixFilesRecursive baseDir;
      attrPaths = map (pathToAttrPath baseDir) files;
      options = buildOptionTree attrPaths;
      
      # Module that defines all the 'enable' options
      optionsModule = { config, lib, ... }: {
        options = lib.setAttrByPath optionPath options;
      };
      
      # List of unconditional imports
      unconditionalModules = map (file: import file) files;
      
    in [ optionsModule ] ++ unconditionalModules; # Return options + all modules

  mkSystem = {    system,              
    hostname,            
    inputs,              
    users ? [],
    overlays ? []      
  }:
  let
    hostsDir = toString ../hosts;
    modulesDir = toString ../modules/nixos;
    homeManagerDir = toString ../home-manager;
    
    homeManagerUsers = lib.listToAttrs (map (user:
      let
        # Define the paths for the two layers
        globalModulesDir = homeManagerDir + "/default";
        userModulesDir = homeManagerDir + "/${user.name}";

        # Find files in both directories, handling non-existent paths
        globalFiles = if builtins.pathExists globalModulesDir then getNixFilesRecursive globalModulesDir else [];
        userFiles = if builtins.pathExists userModulesDir then getNixFilesRecursive userModulesDir else [];

        # Generate attribute paths for each layer separately
        globalAttrPaths = map (pathToAttrPath globalModulesDir) globalFiles;
        userAttrPaths = map (pathToAttrPath userModulesDir) userFiles;

        # Combine attribute paths, taking only unique paths to avoid duplicate option errors
        allAttrPaths = lib.unique (globalAttrPaths ++ userAttrPaths);

        # Build ONE options tree from all unique attribute paths
        options = buildOptionTree allAttrPaths;
        optionsModule = {
          options = lib.setAttrByPath ["my" "homeManager"] options;
        };

        # Import all modules unconditionally. Order matters for overrides.
        globalModules = map (file: import file) globalFiles;
        userModules = map (file: import file) userFiles;

      in
      {
        name = user.name;
        value = {
          # User modules come last to win the merge priority.
          imports = [ optionsModule ] ++ globalModules ++ userModules ++ [
            (import (userModulesDir + "/home.nix"))
          ] ++ (user.homeModules or []);
        };
      }) users);

    nixosModuleSet = mkModuleSet {
      baseDir = modulesDir;
      optionPath = ["my" "nixos"];
    };

  in
  pkgs-unstable.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      {
        nixpkgs = {
          overlays = overlays; 
          config.allowUnfree = true;
        };
      }
      
      # Base-Config for all Systems
      (import (hostsDir + "/default.nix"))
    ] ++ nixosModuleSet ++ [
      # Host-spezifische Konfiguration
      (import (hostsDir + "/${hostname}/configuration.nix"))
      
      home-manager-unstable.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = { inherit inputs; };
          users = homeManagerUsers;
        };
      }
    ];
  };
in {
  inherit mkModuleSet mkSystem;
}