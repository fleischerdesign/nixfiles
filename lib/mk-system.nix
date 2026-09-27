# Multi-architecture NixOS system builder with auto-wired Home Manager and feature auto-discovery.
{
  home-manager-unstable,
  ...
}:
let
  discovery = import ./discovery.nix;

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
      usersLib = import ./users.nix { inherit lib; };
      loader = discovery { inherit lib; };
      featuresDir = ../features;
      allFeatureModules = loader.findModules featuresDir;
      contractsDir = ../contracts;
      allContractModules =
        if builtins.pathExists contractsDir then loader.findModules contractsDir else [ ];

      # The site inventory, composed explicitly and never auto-discovered: subnets, hosts and
      # devices are facts, not modules, so they do not match the nixos.nix marker and are
      # listed here by path instead.
      inventoryModules = map (name: ../inventory + "/${name}.nix") [
        "subnets"
        "hosts"
        "devices"
      ];

      finalPkgs =
        if pkgs != null then
          pkgs
        else
          import inputs.nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };

      userDir = ../user;
      # The same discovery the system module uses: who exists is decided once, from metadata.
      # Home Manager is wired for every discovered user carrying a home profile; a missing
      # home.nix fails loudly below instead of silently dropping the account's environment.
      discoveredUsers = usersLib.discoverNames userDir;

      normalizedUsers =
        if users == [ ] then
          map (name: { inherit name; }) discoveredUsers
        else
          map (
            u:
            u
            // {
              name = u.name or (throw "mkSystem: a users entry names no user: ${builtins.toJSON u}");
            }
          ) users;

      homeManagerUsers = lib.listToAttrs (
        lib.concatMap (
          user:
          let
            homeFile = ../user + "/${user.name}/home.nix";
          in
          if builtins.pathExists homeFile then
            [
              {
                inherit (user) name;
                value = {
                  imports = [ (import homeFile) ] ++ (user.homeModules or [ ]);
                };
              }
            ]
          else
            throw "mkSystem: user/${user.name} has metadata but no home.nix"
        ) normalizedUsers
      );
    in
    inputs.nixpkgs-unstable.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs hostname flake;
        features = import ./feature-dependencies.nix { inherit lib; };
        # Shared fleet resolution, injected once: consumers declare `fleetConfigs` in their
        # arguments instead of importing lib/ by relative path.
        fleetConfigs = import ./fleet-configs.nix { inherit lib; };
      };
      modules = [
        { nixpkgs.pkgs = finalPkgs; }
      ]
      ++ globalModules
      ++ extraModules
      ++ allContractModules
      ++ allFeatureModules
      ++ inventoryModules
      ++ [
        ../hosts/${hostname}/configuration.nix
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
