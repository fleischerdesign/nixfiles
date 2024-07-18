# SPDX-License-Identifier: MIT

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    home-manager.url = "github:nix-community/home-manager?ref=release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, home-manager-unstable, sops-nix, ... }@inputs:
    {
      nixosConfigurations = {
        yorke = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/yorke/configuration.nix
            home-manager.nixosModules.home-manager
          ];
        };

        jello = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/jello/configuration.nix
            home-manager.nixosModules.home-manager
          ];
        };
      };

      hmModules = {
        philipp = {
          imports = [ ./home-manager/philipp/home.nix ];
        };
        server-admin = {
          imports = [ ./home-manager/server-admin/home.nix ];
        };
      };
    };
}
