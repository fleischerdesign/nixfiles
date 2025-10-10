# SPDX-License-Identifier: MIT

{
  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager-stable = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixcord = {
      url = "github:kaylorben/nixcord";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };


  };

  outputs =
    {
      self,
      nixpkgs-stable,
      nixpkgs-unstable,
      home-manager-stable,
      home-manager-unstable,
      nixvim,
      ...
    }@inputs:
    let
      helpers = import ./lib/helper.nix {
        pkgs-unstable = nixpkgs-unstable;
        home-manager-unstable = home-manager-unstable;
      };
    in
    {
      nixosConfigurations = {
        yorke = helpers.mkSystem {
          system = "x86_64-linux";
          hostname = "yorke";
          inputs = inputs;
          overlays = [ (import ./overlays/pip-on-top) ];
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixcord.homeModules.nixcord nixvim.homeManagerModules.nixvim ];
            }
          ];
        };
        jello = helpers.mkSystem {
          system = "x86_64-linux";
          hostname = "jello";
          inputs = inputs;
          overlays = [ (import ./overlays/pip-on-top) ];
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixcord.homeModules.nixcord nixvim.homeManagerModules.nixvim ];
            }
          ];
        };
      };
    };
}
