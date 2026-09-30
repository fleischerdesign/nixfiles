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
      homeUsers ? null,
      usersDir ? ../user,
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

      # A contract may carry an account-scope half beside its host half. The system builder attaches
      # those, because a contract is also evaluated in fixtures that have no `home-manager` module;
      # attaching there instead of inside the contract keeps that host option out of the schema.
      contractHomeModules =
        if builtins.pathExists contractsDir then loader.findNamed "home.nix" contractsDir else [ ];

      # The site inventory, composed explicitly and never auto-discovered: subnets, hosts and
      # devices are facts, not modules, so they do not match the nixos.nix marker and are
      # listed here by path instead.
      inventoryModules = map (name: ../inventory + "/${name}.nix") [
        "subnets"
        "hosts"
        "devices"
        "site"
        "dns"
        "smtp"
        "ssh"
      ];

      finalPkgs =
        if pkgs != null then
          pkgs
        else
          import inputs.nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };

      # Account discovery and Home Manager assignment share usersDir. `homeUsers` selects which
      # discovered accounts receive a Home Manager configuration; null means all, [] means none.
      # System accounts remain the responsibility of the user identity module.
      discoveredUsers = usersLib.discoverNames usersDir;

      normalizedUsers =
        if homeUsers == null then
          map (name: { inherit name; }) discoveredUsers
        else
          map (
            u:
            u
            // {
              name = u.name or (throw "mkSystem: a users entry names no user: ${builtins.toJSON u}");
            }
          ) homeUsers;

      duplicateUsers = lib.unique (
        lib.filter (name: builtins.length (lib.filter (user: user.name == name) normalizedUsers) > 1) (
          map (user: user.name) normalizedUsers
        )
      );

      homeManagerUsers =
        if duplicateUsers != [ ] then
          throw "mkSystem: duplicate user assignments: ${lib.concatStringsSep ", " duplicateUsers}"
        else
          lib.listToAttrs (
            lib.concatMap (
              user:
              let
                homeFile = usersDir + "/${user.name}/home.nix";
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
                throw "mkSystem: ${toString usersDir}/${user.name} has metadata but no home.nix"
            ) normalizedUsers
          );
    in
    inputs.nixpkgs-unstable.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs hostname flake;
        inherit usersDir;
        features = import ./feature-dependencies.nix { inherit lib; };
        # Repository-wide composition helpers are injected once. Contract-owned policy helpers
        # are imported by their consumers from contracts/<domain>/lib, making ownership explicit.
        fleetConfigs = import ./fleet-configs.nix { inherit lib; };
        cidrLib = import ./cidr.nix { inherit lib; };
        inherit usersLib;
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
            # User-level secrets are decrypted by the user's own age identity, not the host key
            # the system module uses. Nothing is decrypted until a user module declares a secret.
            sharedModules = [
              inputs.sops-nix.homeManagerModules.sops
              (
                { config, ... }:
                {
                  sops.age.keyFile = "/home/${config.home.username}/.config/sops/age/keys.txt";
                  sops.defaultSopsFile = ../secrets/secrets.yaml;
                }
              )
            ]
            ++ contractHomeModules;
          };
        }
      ];
    };
in
{
  inherit mkSystem;
}
