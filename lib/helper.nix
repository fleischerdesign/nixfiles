# lib/helper.nix - Snowfall-inspirierte Optimierungen
{ pkgs-unstable, home-manager-unstable, ... }:

let
  lib = pkgs-unstable.lib;

  # === FILE SYSTEM UTILITIES (Snowfall-Style) ===
  
  # Read directory safely
  safeReadDir = dir:
    if builtins.pathExists dir
    then builtins.readDir dir
    else {};

  # Snowfall-style: filterAttrs DANN map (weniger Allokationen)
  getFilesRecursive = dir:
    let
      entries = safeReadDir dir;
      # Filter ZUERST (reduziert Map-Aufrufe)
      filtered = lib.filterAttrs 
        (name: type: type == "directory" || type == "regular") 
        entries;
      
      # Map über gefilterte Einträge
      mapFile = name: type:
        let path = dir + "/${name}";
        in
        if type == "directory" then
          getFilesRecursive path
        else
          [ { inherit name type path; } ];
      
      # Snowfall's map-concat-attrs-to-list Pattern
      files = lib.flatten (lib.mapAttrsToList mapFile filtered);
    in
    files;

  # Filter für .nix Dateien
  filterNixFiles = files:
    builtins.filter (f: 
      lib.hasSuffix ".nix" f.name && f.name != "home.nix"
    ) files;

  # Get nix files - EINMAL scannen, dann filtern
  getNixFiles = dir:
    let
      allFiles = getFilesRecursive dir;
      nixFiles = filterNixFiles allFiles;
    in
    map (f: f.path) nixFiles;

  # === OPTION GENERATION ===

  pathToAttrPath = baseDir: filePath:
    let
      relativePath = lib.removePrefix (toString baseDir + "/") (toString filePath);
      pathWithoutNix = lib.removeSuffix ".nix" relativePath;
      pathWithoutDefault = if lib.hasSuffix "/default" pathWithoutNix
                         then lib.removeSuffix "/default" pathWithoutNix
                         else pathWithoutNix;
    in
    lib.splitString "/" pathWithoutDefault;

  # Optimiert: Direkte Optionsgenerierung
  mkOptions = attrPaths:
    let
      mkSingleOption = path: {
        path = path;
        option = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable module '${lib.concatStringsSep "." path}'";
        };
      };
      
      # Baue verschachtelte Struktur
      setAtPath = acc: item:
        lib.setAttrByPath item.path { enable = item.option; } // acc;
      
      options = map mkSingleOption attrPaths;
    in
    lib.foldl' (acc: item: lib.recursiveUpdate acc (setAtPath {} item)) {} options;

  # === MODULE SYSTEM ===

  mkModuleOptions = { baseDir, optionPath }:
    let
      files = getNixFiles baseDir;
      attrPaths = map (pathToAttrPath baseDir) files;
      options = mkOptions attrPaths;
    in
    { options = lib.setAttrByPath optionPath options; };

  mkModuleSet = { baseDir, optionPath }:
    let
      files = getNixFiles baseDir;
      modules = map (file: import file) files;
      optionsModule = mkModuleOptions { inherit baseDir optionPath; };
    in
    [ optionsModule ] ++ modules;

  # === SYSTEM BUILDER ===

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

    # Scanne alle User-Verzeichnisse EINMAL
    userDirs = lib.filterAttrs (n: t: t == "directory" && n != "default") 
      (safeReadDir homeManagerDir);

    mkHomeManagerUserConfig = user:
      let
        globalModulesDir = homeManagerDir + "/default";
        userModulesDir = homeManagerDir + "/${user.name}";

        # Einmal scannen
        globalFiles = getNixFiles globalModulesDir;
        userFiles = getNixFiles userModulesDir;
        
        globalModules = map (f: import f) globalFiles;
        
        userAttrPaths = map (pathToAttrPath userModulesDir) userFiles;
        userOptions = mkOptions userAttrPaths;
        userOptionsModule = { 
          options = lib.setAttrByPath ["my" "homeManager"] userOptions; 
        };
        userModules = map (f: import f) userFiles;
      in
      {
        name = user.name;
        value = {
          imports = 
            [ userOptionsModule ]
            ++ globalModules
            ++ userModules 
            ++ [ (import (userModulesDir + "/home.nix")) ]
            ++ (user.homeModules or []);
        };
      };

    homeManagerUsers = lib.listToAttrs (map mkHomeManagerUserConfig users);
    nixosModuleSet = mkModuleSet { 
      baseDir = modulesDir; 
      optionPath = ["my" "nixos"]; 
    };

  in
  pkgs-unstable.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      { nixpkgs = { inherit overlays; config.allowUnfree = true; }; }
      (import (hostsDir + "/base.nix"))
    ] ++ nixosModuleSet ++ [
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
  inherit mkModuleOptions mkModuleSet mkSystem getNixFiles;
}
