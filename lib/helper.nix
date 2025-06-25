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
             && name != "default.nix" then
          [ path ]
        else [];
    in lib.flatten (lib.mapAttrsToList processEntry entries);
  
  pathToAttrPath = baseDir: filePath:
    let
      relativePath = lib.removePrefix (toString baseDir + "/") (toString filePath);
      cleanedPath = lib.removeSuffix ".nix" relativePath;
    in
    lib.splitString "/" cleanedPath;
  
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

  # Wrapper-Funktion, die ein Modul bedingt macht
  makeConditionalModule = { modulePath, optionPath }:
    { config, lib, pkgs, ... }:
    let
      isEnabled = lib.getAttrFromPath optionPath config;
      originalModule = import modulePath;
      moduleContent = if builtins.isFunction originalModule
                      then originalModule { inherit config lib pkgs; }
                      else originalModule;
    in {
      config = lib.mkIf isEnabled (moduleContent.config or moduleContent);
    };

  mkModuleSet = { baseDir, optionPath ? ["my" "modules"] }:
    let
      files = getNixFilesRecursive baseDir;
      attrPaths = map (pathToAttrPath baseDir) files;
      options = buildOptionTree attrPaths;
      
      # Erstelle das Optionen-Modul
      optionsModule = { config, lib, ... }: {
        options = lib.setAttrByPath optionPath options;
      };
      
      # Erstelle bedingte Module für jede Datei
      conditionalModules = lib.zipListsWith (attrPath: file: 
        makeConditionalModule {
          modulePath = file;
          optionPath = optionPath ++ attrPath ++ ["enable"];
        }
      ) attrPaths files;
      
    in [ optionsModule ] ++ conditionalModules;

  mkSystem = { 
    system,              
    hostname,            
    inputs,              
    users ? []      
  }:
  let
    hostsDir = toString ../hosts;
    modulesDir = toString ../modules/nixos;
    homeManagerDir = toString ../home-manager;
    
    homeManagerUsers = lib.listToAttrs (map (user: {
      name = user.name;
      value = {
        imports = [
          (import (homeManagerDir + "/${user.name}/home.nix"))
        ] ++ (user.homeModules or []);
      };
    }) users);

    moduleSet = mkModuleSet {
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
          overlays = []; 
          config.allowUnfree = true;
        };
      }
      
      # Base-Config for all Systems
      (import (hostsDir + "/base.nix"))
    ] ++ moduleSet ++ [
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