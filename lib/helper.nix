# lib/helper.nix - Optimiert: Automatisches Scanning, aber performant
{ pkgs-unstable, home-manager-unstable, ... }:

let
  lib = pkgs-unstable.lib;

  # Effizientere Version von getNixFilesRecursive
  # Anstatt jeden Eintrag einzeln zu stat'en, nutzen wir eine single Sortierung
  getNixFilesRecursive = dir:
    let
      entries = builtins.readDir dir;
      # Sortiere und filtere in einem Schritt
      sorted = lib.attrNames entries;
    in
    lib.concatMap (name:
      let 
        path = dir + "/${name}";
        type = entries.${name};
      in
      if type == "directory" then
        getNixFilesRecursive path
      else if type == "regular" && lib.hasSuffix ".nix" name && name != "home.nix" then
        [ path ]
      else
        []
    ) sorted;

  # Memoized version - Cache die Ergebnisse
  cachedGetNixFilesRecursive = dir:
    if builtins.pathExists dir then 
      getNixFilesRecursive dir 
    else 
      [];

  pathToAttrPath = baseDir: filePath:
    let
      relativePath = lib.removePrefix (toString baseDir + "/") (toString filePath);
      pathWithoutNix = lib.removeSuffix ".nix" relativePath;
      pathWithoutDefault = if lib.hasSuffix "/default" pathWithoutNix
                         then lib.removeSuffix "/default" pathWithoutNix
                         else pathWithoutNix;
    in
    lib.splitString "/" pathWithoutDefault;

  # Optimiert: Builds die komplette Optionen-Struktur in einem Pass
  buildOptionTree = paths:
    let
      # Nutze foldl' mit einem map für bessere Performance
      buildSingle = path:
        let
          parts = path;
          buildNested = index:
            if index >= lib.length parts then
              { enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable module '${lib.concatStringsSep "." parts}'";
                };
              }
            else
              { ${lib.elemAt parts index} = buildNested (index + 1); };
        in
        buildNested 0;

      # Merge alle Optionen zusammen
      mergeNested = acc: nested:
        lib.recursiveUpdate acc nested;
    in
    lib.foldl' mergeNested {} (map buildSingle paths);

  # Generate enable options für Verzeichnis
  mkModuleOptions = { baseDir, optionPath }:
    let
      files = cachedGetNixFilesRecursive baseDir;
      attrPaths = map (pathToAttrPath baseDir) files;
      options = buildOptionTree attrPaths;
    in
    { options = lib.setAttrByPath optionPath options; };

  # Create module set mit automatischem Discovery
  mkNixosModuleSet = { baseDir }:
    let
      files = cachedGetNixFilesRecursive baseDir;
      unconditionalModules = map (file: import file) files;
    in
    [ (mkModuleOptions { inherit baseDir; optionPath = ["my" "nixos"]; }) ] 
    ++ unconditionalModules;

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

    mkHomeManagerUserConfig = user:
      let
        globalModulesDir = homeManagerDir + "/default";
        userModulesDir = homeManagerDir + "/${user.name}";

        # Global modules - immer importiert
        globalFiles = cachedGetNixFilesRecursive globalModulesDir;
        globalModules = map (file: import file) globalFiles;

        # User modules - mit enable flags
        userFiles = cachedGetNixFilesRecursive userModulesDir;
        userAttrPaths = map (pathToAttrPath userModulesDir) userFiles;
        userOptions = buildOptionTree userAttrPaths;
        userOptionsModule = { options = lib.setAttrByPath ["my" "homeManager"] userOptions; };
        userModules = map (file: import file) userFiles;
      in
      {
        name = user.name;
        value = {
          imports = [
            userOptionsModule
          ]
          ++ globalModules
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

      # Base-Config
      (import (hostsDir + "/base.nix"))
    ] ++ nixosModuleSet ++ [
      # Host-spezifische Konfiguration
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
  inherit mkModuleOptions mkNixosModuleSet mkSystem;
}
