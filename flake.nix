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
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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

    vyrx-landing = {
      url = "github:fleischerdesign/vyrx.de";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nod = {
      url = "github:fleischerdesign/nod/develop";
      inputs.nixpkgs-unstable.follows = "nixpkgs-unstable";
    };

    openclaw = {
      url = "github:openclaw/nix-openclaw";
    };

    # The two agent tools follow `main` between nixpkgs releases on purpose: both projects move
    # faster than nixpkgs' tagged packages, and their flakes pin the rest of their input graph.
    # nixpkgs still supplies the Hub, which has no flake of its own.
    pi = {
      url = "github:earendil-works/pi";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    paseo = {
      url = "github:getpaseo/paseo";
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
        (import ./packages/overlays/fix/bottles)
        (import ./packages/overlays/fix/authentik)
        (import ./packages/overlays/fix/paperless-ngx)
        (import ./packages/overlays/fix/moonraker)
        (import ./packages/overlays/fix/paseo-desktop inputs.paseo)
        inputs.nix-vscode-extensions.overlays.default
        (import ./packages/custom)
      ];

      # Central nixpkgs instance with fleet-wide package configuration.
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
        inputs.nod.nixosModules.default
      ];
      hostNames = nixpkgs-unstable.lib.attrNames (
        nixpkgs-unstable.lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./hosts + "/${name}/configuration.nix")
        ) (builtins.readDir ./hosts)
      );

      # Every host that runs the authentik server ships a compiled blueprint directory. The check below
      # proves those bytes before a deploy, so a bad model name, a cross-file reference or a person who
      # is declared instead of seeded fails here instead of on the identity provider.
      blueprintHosts = nixpkgs-unstable.lib.filter (
        name: self.nixosConfigurations.${name}.config.my.features.services.authentik.server.enable or false
      ) hostNames;

      # One argument set for every file-based check: each check declares the slice it needs and
      # ignores the rest, so adding a check never re-lists pkgs/lib/inputs/self.
      checkArgs = {
        inherit
          pkgs
          self
          hostNames
          blueprintHosts
          inputs
          ;
        lib = nixpkgs-unstable.lib;
      };
    in
    {
      # The fleet declaration for nod (ADR-031): the same structure the
      # configuration file uses, evaluated by nod with `nix eval`.
      # `nix flake check` reports "unknown flake output 'nod'" because the name is
      # outside the flake schema. The warning is expected: this output is the
      # contract with the reconciler, not a misspelling.
      nod = self.nixosConfigurations.cld-ops-01.config.services.nod.fleet;
      formatter.${system} = pkgs.nixfmt-tree;

      packages.${system} = pkgs.custom // {
        authentik-desired =
          self.nixosConfigurations.cld-edge-01.config.my.features.services.authentik.server.nodDesiredStatePackage;
        nod-provider-authentik = self.inputs.nod.packages.${system}.nod-provider-authentik;
      };

      apps.${system} = {
        update-custom-packages = {
          type = "app";
          program = "${
            pkgs.writeShellApplication {
              name = "update-custom-packages-app";
              runtimeInputs = with pkgs; [
                bash
                curl
                jq
                nix
                nodejs
                coreutils
                gnused
                gawk
                gnugrep
                gnutar
                gzip
                (python3.withPackages (ps: [ ps.pyyaml ]))
                findutils
                git
              ];
              text = "exec ${./apps/update-custom-packages}/update-custom-packages.sh \"$@\"";
            }
          }/bin/update-custom-packages-app";
          meta = {
            description = "Auto-update engine for custom packages in packages/custom";
          };
        };

        network-audit = {
          type = "app";
          program = "${
            (import ./apps/network-audit {
              inherit pkgs hostNames self;
              lib = nixpkgs-unstable.lib;
            })
          }/bin/network-audit";
          meta = {
            description = "Measure the fleet against what the inventory promises";
          };
        };

        # An inventory of every listening socket outside loopback and whether it is a decision somebody
        # made. `--strict` turns it into the gate that keeps a new service from being exposed by accident.
        exposure-audit = {
          type = "app";
          program = "${
            (import ./apps/exposure-audit {
              inherit pkgs hostNames self;
              lib = nixpkgs-unstable.lib;
            })
          }/bin/exposure-audit";
          meta = {
            description = "List every listening socket and whether it was declared";
          };
        };
      };

      # The check surface is discovered, not listed: `checks/<name>.nix` is a check and the file name
      # is the output name (lib/checks.nix).
      checks.${system} = import ./checks checkArgs;

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

      # Agentless targets are addressed from the inventory, not literals: the projection
      # refuses a target without an address, so a renamed device cannot silently keep its
      # old one here.
      nodTargets =
        let
          inventoryHosts = self.nixosConfigurations.cld-edge-01.config.my.topology.hosts;
          targets = {
            hom-rt-01 = {
              targetHost = inventoryHosts.hom-rt-01.ipv4 or null;
              role = "router";
              targetType = "agentless";
              tags = [
                "router"
                "tr064"
                "gitops"
              ];
              package = self.nixosConfigurations.hom-srv-01.config.my.features.system.networking.fritzbox.package;
            };

            hom-ap-01 = {
              targetHost = inventoryHosts.hom-ap-01.ipv4 or null;
              role = "embedded";
              targetType = "agentless";
              tags = [
                "ap"
                "wifi"
                "gitops"
              ];
              package =
                self.nixosConfigurations.hom-srv-01.config.my.features.system.networking.tplink-ap.package;
            };
          }
          // (builtins.mapAttrs (devName: devPkg: {
            targetHost = self.nixosConfigurations.hom-srv-01.config.my.topology.devices.${devName}.ipv4;
            role = "embedded";
            targetType = "agentless";
            tags = [
              "esphome"
              "iot"
              "gitops"
            ];
            package = devPkg;
          }) self.nixosConfigurations.hom-srv-01.config.my.features.services.esphome.devicePackages);
          withoutAddress = nixpkgs-unstable.lib.filter (name: (targets.${name}.targetHost or null) == null) (
            builtins.attrNames targets
          );
        in
        assert
          withoutAddress == [ ]
          || throw "nodTargets without a targetHost: ${nixpkgs-unstable.lib.concatStringsSep ", " withoutAddress}";
        targets;

      # The binary cache CI pulls from, derived from the service contract so the workflow names no
      # contract path of its own: a reshape changes this definition, not the workflow. The one
      # provider comes from the feature switch, never from a host literal.
      binaryCache =
        let
          providers = builtins.filter (host: host.config.my.features.services.attic.server.enable or false) (
            builtins.attrValues self.nixosConfigurations
          );
          provider = builtins.head providers;
          endpoint = "https://${provider.config.my.contracts.provides.attic.publications.web.canonicalDomain}";
        in
        assert
          builtins.length providers == 1
          || throw "binaryCache: expected exactly one Attic server, found ${toString (builtins.length providers)}";
        {
          inherit endpoint;
          cache = provider.config.my.features.services.attic.server.cache;
          substituter = "${endpoint}/${provider.config.my.features.services.attic.server.cache}";
          keys = provider.config.nix.settings.trusted-public-keys;
        };
    };
}
