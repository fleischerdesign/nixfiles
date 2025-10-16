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
        else[];
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

  # Safely read .nix files, handling non-existent directories
  safeGetNixFiles = dir:
    if builtins.pathExists dir then getNixFilesRecursive dir else [];

  # Generate enable options for a given base directory
  # Used for both NixOS and Home Manager modules
  mkModuleOptions = { baseDir, optionPath }:
    let
      files = safeGetNixFiles baseDir;
      attrPaths = map (pathToAttrPath baseDir) files;
      options = buildOptionTree attrPaths;
    in
    {
      options = lib.setAttrByPath optionPath options;
    };

  # Create a modular set for a given directory
  # Automatically discovers and imports all .nix files
  mkNixosModuleSet = { baseDir }:
    let
      files = safeGetNixFiles baseDir;
      unconditionalModules = map (file: import file) files;
    in
    [ (mkModuleOptions { inherit baseDir; optionPath = ["my" "nixos"]; }) ] ++ unconditionalModules;

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
    
    # Helper to create Home Manager user configuration
    mkHomeManagerUserConfig = user:
      let
        globalModulesDir = homeManagerDir + "/default";
        userModulesDir = homeManagerDir + "/${user.name}";

        # Global modules are always imported, without 'enable' flags
        globalFiles = safeGetNixFiles globalModulesDir;
        globalModules = map (file: import file) globalFiles;

        # User modules get 'enable' flags under 'my.homeManager'
        userFiles = safeGetNixFiles userModulesDir;
        userAttrPaths = map (pathToAttrPath userModulesDir) userFiles;
        userOptions = buildOptionTree userAttrPaths;
        userOptionsModule = { options = lib.setAttrByPath ["my" "homeManager"] userOptions; };
        userModules = map (file: import file) userFiles;
      in
      {
        name = user.name;
        value = {
          imports = [
            # Only create 'enable' options for user-specific modules
            userOptionsModule
          ]
          # Global modules are always imported unconditionally
          ++ globalModules
          # User modules are also imported, but are guarded by the 'enable' flags inside their files
          ++ userModules ++ [
            (import (userModulesDir + "/home.nix"))
          ] ++ (user.homeModules or []);
        };
      };

    homeManagerUsers = lib.listToAttrs (map mkHomeManagerUserConfig users);
    nixosModuleSet = mkNixosModuleSet { baseDir = modulesDir; };

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
      (import (hostsDir + "/base.nix"))
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
  inherit mkModuleOptions mkNixosModuleSet mkSystem;
}
