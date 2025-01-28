# SPDX-License-Identifier: MIT

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    sops-nix.url = "github:Mic92/sops-nix";

    home-manager.url = "github:nix-community/home-manager?ref=release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-unstable.url = "github:nix-community/home-manager";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";

    zen-browser.url = "github:0xc000022070/zen-browser-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      home-manager-unstable,
      sops-nix,
      zen-browser,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        yorke = nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/yorke/configuration.nix
            home-manager-unstable.nixosModules.home-manager
            { _module.args = { inherit inputs; }; }
          ];
        };

        jello = nixpkgs-unstable.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/jello/configuration.nix
            home-manager-unstable.nixosModules.home-manager
            { _module.args = { inherit inputs; }; }
          ];
        };
      };

      hmModules = {
        philipp = {
          imports = [
            ./home-manager/philipp/home.nix
            inputs.sops-nix.homeManagerModules.sops
          ];
          _module.args = { inherit inputs; };
        };
        server-admin = {
          imports = [ ./home-manager/server-admin/home.nix ];
          _module.args = { inherit inputs; };
        };
      };
    };
}
