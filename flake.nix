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

    figma-linux.url = "github:HelloWorld017/figma-linux-nixos";
    figma-linux.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nix4vscode.url = "github:nix-community/nix4vscode";
    nix4vscode.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      home-manager-unstable,
      sops-nix,
      figma-linux,
      nix4vscode,
      ...
    }@inputs:
    let
      mkSystem = system: hostname: extraModules:
        inputs.nixpkgs-unstable.lib.nixosSystem {
          inherit system;
          # Inputs übergeben
          specialArgs = { inherit inputs; };
          modules = [
            # Inline-Modul zum Setzen von nixpkgs Konfigurationen
            ({ config, pkgs, inputs, ... }: {
              nixpkgs = {
                # Dein Overlay von vorher
                overlays = [ nix4vscode.overlays.forVscode ];

                # Hier die Konfiguration für allowUnfree hinzufügen:
                config = {
                  allowUnfree = true;
                };
              };
            })

            # Deine bestehenden Module
            ./hosts/${hostname}/configuration.nix
            inputs.home-manager-unstable.nixosModules.home-manager
          ] ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        yorke = mkSystem "x86_64-linux" "yorke" [ ];
        jello = mkSystem "x86_64-linux" "jello" [ ];
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
