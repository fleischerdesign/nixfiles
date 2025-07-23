# SPDX-License-Identifier: MIT

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    figma-linux = {
      url = "github:HelloWorld017/figma-linux-nixos";
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
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      home-manager-unstable,
      figma-linux,
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
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixcord.homeModules.nixcord inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
        jello = helpers.mkSystem {
          system = "x86_64-linux";
          hostname = "jello";
          inputs = inputs;
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixcord.homeModules.nixcord inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
      };
    };
}
