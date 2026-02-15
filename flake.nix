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

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    portfolio = {
      url = "github:fleischerdesign/portfolio";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    firefox-gnome-theme = {
      url = "github:rafaelmardojai/firefox-gnome-theme";
      flake = false;
    };

    thunderbird-gnome-theme = {
      url = "github:rafaelmardojai/thunderbird-gnome-theme";
      flake = false;
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
      disko,
      portfolio,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      
      # Zentralisierte Overlays
      overlays = [
        (import ./overlays/pip-on-top)
        inputs.nix-vscode-extensions.overlays.default
      ];

      # Zentrale Nixpkgs Instanz mit globaler Config
      pkgs = import nixpkgs-unstable {
        inherit system overlays;
        config.allowUnfree = true;
      };

      helpers = import ./lib/helper.nix {
        inherit pkgs;
        home-manager-unstable = home-manager-unstable;
      };
    in
    {
      nixosConfigurations = {
        yorke = helpers.mkSystem {
          inherit system pkgs inputs;
          hostname = "yorke";
          extraModules = [ inputs.niri.nixosModules.niri ];
          users = [
            {
              name = "philipp";
              homeModules = [
                inputs.nixcord.homeModules.nixcord
                inputs.spicetify-nix.homeManagerModules.default
                inputs.nixvim.homeModules.nixvim
              ];
            }
          ];
        };
        jello = helpers.mkSystem {
          inherit system pkgs inputs;
          hostname = "jello";
          extraModules = [ inputs.niri.nixosModules.niri ];
          users = [
            {
              name = "philipp";
              homeModules = [
                inputs.nixcord.homeModules.nixcord
                inputs.spicetify-nix.homeManagerModules.default
                inputs.nixvim.homeModules.nixvim
              ];
            }
          ];
        };
        strummer = helpers.mkSystem {
          inherit system pkgs inputs;
          hostname = "strummer";
          users = [
            {
              name = "philipp";
              homeModules = [ inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
        mackaye = helpers.mkSystem {
          inherit system pkgs inputs;
          hostname = "mackaye";
          extraModules = [ inputs.disko.nixosModules.disko ];
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