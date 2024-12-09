# SPDX-License-Identifier: MIT

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager?ref=release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, home-manager-unstable, agenix, ... }@inputs:
    {
      nixosConfigurations = {
        yorke = nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/yorke/configuration.nix
            agenix.nixosModules.default
            home-manager-unstable.nixosModules.home-manager
            { _module.args = { inherit inputs; }; }
          ];
        };

        jello = nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/jello/configuration.nix
            agenix.nixosModules.default
            home-manager-unstable.nixosModules.home-manager
            { _module.args = { inherit inputs; }; }
          ];
        };
      };

      hmModules = {
        philipp = {
          imports = [ ./home-manager/philipp/home.nix agenix.homeManagerModules.default ];
          _module.args = { inherit inputs; };
        };
        server-admin = {
          imports = [ ./home-manager/server-admin/home.nix ];
          _module.args = { inherit inputs; };
        };
      };
    };
}
