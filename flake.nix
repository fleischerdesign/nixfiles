# SPDX-License-Identifier: MIT

{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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

    portfolio = {
      url = "github:fleischerdesign/portfolio";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    axis = {
      url = "github:fleischerdesign/Axis/develop";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    hermes-webui = {
      url = "github:nesquena/hermes-webui";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      home-manager-unstable,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      flake = self;

      # Zentralisierte Overlays
      overlays = [
        (import ./overlays/fix/patool)
        (import ./overlays/fix/inline-snapshot)
        (import ./overlays/fix/hermes-agent inputs)
        inputs.nix-vscode-extensions.overlays.default
      ];

      # Zentrale Nixpkgs Instanz mit globaler Config
      pkgs = import nixpkgs-unstable {
        inherit system overlays;
        config = {
          allowUnfree = true;
          # TODO: remove when nixpkgs fixes pnpm 10.34.0 CVEs upstream
          # pnpm_10_34_0 was pinned for packages that don't support 10.34.1+ breaking change
          permittedInsecurePackages = [ "pnpm-10.34.0" ];
        };
      };

      helpers = import ./lib {
        inherit home-manager-unstable;
      };

      globalModules = [
        inputs.sops-nix.nixosModules.sops
      ];
    in
    {
      formatter.${system} = pkgs.nixfmt;

      checks.${system} = {
        eval-hosts = pkgs.runCommandLocal "eval-all-hosts" { } ''
          echo "yorke: ${builtins.unsafeDiscardStringContext self.nixosConfigurations.yorke.config.system.build.toplevel.drvPath}" > $out
          echo "jello: ${builtins.unsafeDiscardStringContext self.nixosConfigurations.jello.config.system.build.toplevel.drvPath}" >> $out
          echo "strummer: ${builtins.unsafeDiscardStringContext self.nixosConfigurations.strummer.config.system.build.toplevel.drvPath}" >> $out
          echo "mackaye: ${builtins.unsafeDiscardStringContext self.nixosConfigurations.mackaye.config.system.build.toplevel.drvPath}" >> $out
          echo "rollins: ${builtins.unsafeDiscardStringContext self.nixosConfigurations.rollins.config.system.build.toplevel.drvPath}" >> $out
        '';

        statix = pkgs.runCommandLocal "statix-check" {
          nativeBuildInputs = [ pkgs.statix ];
        } ''
          statix check ${./.} || true
          touch $out
        '';

        deadnix = pkgs.runCommandLocal "deadnix-check" {
          nativeBuildInputs = [ pkgs.deadnix ];
        } ''
          deadnix --fail ${./.}
          touch $out
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt
          deadnix
          statix
          nil
          sops
          age
        ];
      };

      nixosConfigurations = {
        yorke = helpers.mkSystem {
          inherit
            system
            pkgs
            inputs
            flake
            globalModules
            ;
          hostname = "yorke";
          extraModules = [
            inputs.niri.nixosModules.niri
            inputs.axis.nixosModules.default
          ];
          users = [
            {
              extraGroups = [
                "networkmanager"
                "wheel"
                "adbusers"
                "input"
                "uinput"
              ];
              homeModules = [
                inputs.nixcord.homeModules.nixcord
                inputs.spicetify-nix.homeManagerModules.default
                inputs.nixvim.homeModules.nixvim
              ];
            }
          ];
        };
        jello = helpers.mkSystem {
          inherit
            system
            pkgs
            inputs
            flake
            globalModules
            ;
          hostname = "jello";
          extraModules = [
            inputs.niri.nixosModules.niri
            inputs.axis.nixosModules.default
          ];
          users = [
            {
              extraGroups = [
                "networkmanager"
                "wheel"
                "adbusers"
                "input"
                "uinput"
              ];
              homeModules = [
                inputs.nixcord.homeModules.nixcord
                inputs.spicetify-nix.homeManagerModules.default
                inputs.nixvim.homeModules.nixvim
              ];
            }
          ];
        };
        strummer = helpers.mkSystem {
          inherit
            system
            pkgs
            inputs
            flake
            globalModules
            ;
          hostname = "strummer";
          users = [
            {
              extraGroups = [
                "networkmanager"
                "wheel"
                "media"
              ];
              homeModules = [ inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
        mackaye = helpers.mkSystem {
          inherit
            system
            pkgs
            inputs
            flake
            globalModules
            ;
          hostname = "mackaye";
          extraModules = [ inputs.disko.nixosModules.disko ];
          users = [
            {
              extraGroups = [
                "networkmanager"
                "wheel"
              ];
              homeModules = [ inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
        rollins = helpers.mkSystem {
          inherit
            system
            pkgs
            inputs
            flake
            globalModules
            ;
          hostname = "rollins";
          extraModules = [ inputs.disko.nixosModules.disko ];
          users = [
            {
              extraGroups = [
                "networkmanager"
                "wheel"
              ];
              homeModules = [ inputs.nixvim.homeModules.nixvim ];
            }
          ];
        };
      };

      deploy = {
        autoRollback = true;
        magicRollback = false;

        nodes = builtins.mapAttrs (
          name: _:
          let
            hostConfig = self.nixosConfigurations.${name};
          in
          {
            hostname = hostConfig.config.my.features.system.networking.topology.hosts.${name}.tailscaleIp;
            profiles.system = {
              user = "root";
              sshUser = "root";
              sshOpts = [
                "-i"
                "/home/philipp/.ssh/deploy-key"
              ];
              path = inputs.deploy-rs.lib.${system}.activate.nixos hostConfig;
            };
          }
        ) self.nixosConfigurations;
      };
    };
}
