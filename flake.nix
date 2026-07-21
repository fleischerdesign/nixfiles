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
        (import ./packages/overlays/fix/patool)
        (import ./packages/overlays/fix/inline-snapshot)
        (import ./packages/overlays/fix/hermes-agent inputs)
        inputs.nix-vscode-extensions.overlays.default
        (import ./packages/custom)
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
      hostNames = nixpkgs-unstable.lib.attrNames (
        nixpkgs-unstable.lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./hosts + "/${name}/configuration.nix")
        ) (builtins.readDir ./hosts)
      );
    in
    {
      formatter.${system} = pkgs.nixfmt;

      packages.${system} = pkgs.custom;

      apps.${system}.update-custom-packages = {
        type = "app";
        program = "${
          pkgs.writeShellApplication {
            name = "update-custom-packages-app";
            runtimeInputs = with pkgs; [
              bash
              curl
              jq
              nix
              coreutils
              gnused
              findutils
            ];
            text = "exec ${./lib/updaters/update-custom-packages.sh} \"$@\"";
          }
        }/bin/update-custom-packages-app";
        meta = {
          description = "Auto-update engine for custom packages in packages/custom";
        };
      };

      checks.${system} = {
        eval-hosts = pkgs.runCommandLocal "eval-all-hosts" { } (
          nixpkgs-unstable.lib.concatMapStringsSep "\n" (
            name:
            "echo \"${name}: ${
              builtins.unsafeDiscardStringContext
                self.nixosConfigurations.${name}.config.system.build.toplevel.drvPath
            }\" >> $out"
          ) hostNames
        );

        statix =
          pkgs.runCommandLocal "statix-check"
            {
              nativeBuildInputs = [ pkgs.statix ];
            }
            ''
              statix check ${./.} || true
              touch $out
            '';

        deadnix =
          pkgs.runCommandLocal "deadnix-check"
            {
              nativeBuildInputs = [ pkgs.deadnix ];
            }
            ''
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

      nixosConfigurations = nixpkgs-unstable.lib.genAttrs hostNames (
        hostname:
        helpers.mkSystem {
          inherit
            system
            pkgs
            inputs
            flake
            globalModules
            hostname
            ;
        }
      );

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
