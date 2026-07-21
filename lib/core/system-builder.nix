# lib/core/system-builder.nix
# Multi-architecture NixOS system builder with auto-wired Home Manager and feature auto-discovery.
{
  home-manager-unstable,
  ...
}:
let
  moduleLoader = import ./module-loader.nix;

  mkSystem =
    {
      system ? "x86_64-linux",
      pkgs ? null,
      hostname,
      inputs,
      flake ? null,
      users ? [ ],
      extraModules ? [ ],
      globalModules ? [ ],
    }:
    let
      inherit (inputs.nixpkgs-unstable) lib;
      loader = moduleLoader { inherit lib; };
      featuresDir = ../../features;
      allFeatureModules = loader.findModules featuresDir;

      finalPkgs =
        if pkgs != null then
          pkgs
        else
          import inputs.nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };

      userDir = ../../user;
      discoveredUsers =
        if builtins.pathExists userDir then
          lib.filter (
            name: builtins.pathExists (userDir + "/${name}/home.nix")
          ) (builtins.attrNames (builtins.readDir userDir))
        else
          [ ];

      defaultUserName = if discoveredUsers != [ ] then lib.head discoveredUsers else "philipp";

      normalizedUsers =
        if users == [ ] then
          map (name: { inherit name; }) discoveredUsers
        else
          map (u: u // { name = u.name or defaultUserName; }) users;

      homeManagerUsers = lib.listToAttrs (
        map (user: {
          inherit (user) name;
          value = {
            imports = [ (import (../../user + "/${user.name}/home.nix")) ] ++ (user.homeModules or [ ]);
          };
        }) normalizedUsers
      );
    in
    inputs.nixpkgs-unstable.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs hostname flake;
        features = import ../features.nix { inherit lib; };
      };
      modules = [
        { nixpkgs.pkgs = finalPkgs; }
      ]
      ++ globalModules
      ++ extraModules
      ++ allFeatureModules
      ++ [
        ../../hosts/${hostname}/configuration.nix
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
in
{
  inherit mkSystem;
}
