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

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
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
      spicetify-nix,
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
          extraModules = [ inputs.niri.nixosModules.niri ];
          overlays = [ (import ./overlays/pip-on-top) inputs.nix-vscode-extensions.overlays.default ];
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixcord.homeModules.nixcord inputs.spicetify-nix.homeManagerModules.default inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
        jello = helpers.mkSystem {
          system = "x86_64-linux";
          hostname = "jello";
          inputs = inputs;
          extraModules = [ inputs.niri.nixosModules.niri ];
          overlays = [ (import ./overlays/pip-on-top) inputs.nix-vscode-extensions.overlays.default ];
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixcord.homeModules.nixcord inputs.spicetify-nix.homeManagerModules.default inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
        strummer = helpers.mkSystem {
          system = "x86_64-linux";
          hostname = "strummer";
          inputs = inputs;
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
      };
    };
}
