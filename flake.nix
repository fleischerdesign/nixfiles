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

    axis = {
      url = "github:fleischerdesign/Axis/develop";
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
        inputs.nix-vscode-extensions.overlays.default
        inputs.openclaw.overlays.default
        (import ./packages/overlays/fix/openclaw)
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
        inputs.nod.nixosModules.default
        inputs.openclaw.nixosModules.openclaw-gateway
      ];
      hostNames = nixpkgs-unstable.lib.attrNames (
        nixpkgs-unstable.lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./hosts + "/${name}/configuration.nix")
        ) (builtins.readDir ./hosts)
      );

      # Every host that runs the OpenClaw gateway gets its rendered config validated
      # against the upstream schema at build time; `services.openclaw-gateway.config`
      # itself is only checked with `builtins.isAttrs`.
      gatewayHosts = nixpkgs-unstable.lib.filter (
        name: self.nixosConfigurations.${name}.config.services.openclaw-gateway.enable
      ) hostNames;
    in
    {
      formatter.${system} = pkgs.nixfmt;

      packages.${system} = pkgs.custom;

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
                findutils
              ];
              text = "exec ${./lib/updaters/update-custom-packages.sh} \"$@\"";
            }
          }/bin/update-custom-packages-app";
          meta = {
            description = "Auto-update engine for custom packages in packages/custom";
          };
        };

        sync-cloudflare = {
          type = "app";
          program = "${self.nixosConfigurations.cld-edge-01.config.my.features.system.networking.cloudflare.package}/bin/cloudflare-sync";
          meta = {
            description = "Declarative Cloudflare Edge & DNS GitOps Reconciliation Tool";
          };
        };
        network-audit = {
          type = "app";
          program = "${
            (import ./lib/audit/default.nix {
              inherit pkgs hostNames self;
              lib = nixpkgs-unstable.lib;
            }).network
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
            (import ./lib/audit/default.nix {
              inherit pkgs hostNames self;
              lib = nixpkgs-unstable.lib;
            }).exposure
          }/bin/exposure-audit";
          meta = {
            description = "List every listening socket and whether it was declared";
          };
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
              statix check --config ${./statix.toml} ${./.}
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

        # The promises the network makes, checked against the evaluated fleet. The assertions in the
        # modules catch a bad declaration; this catches a fleet whose parts contradict each other - a
        # carried zone without a forward rule, a name that answers with an address nothing routes, a
        # client that routes a home zone. Every one of them was a real failure before it was a check.
        network-invariants =
          let
            result = import ./lib/checks/network-invariants.nix {
              lib = nixpkgs-unstable.lib;
              inherit self hostNames;
            };
          in
          pkgs.runCommandLocal "network-invariants" { } (
            if result.violations == [ ] then
              "echo 'ok: ${toString (builtins.length result.invariants)} network invariants hold' > $out"
            else
              ''
                cat >&2 <<'VIOLATIONS'
                ${nixpkgs-unstable.lib.concatStringsSep "\n" result.violations}
                VIOLATIONS
                exit 1
              ''
          );
      }
      // nixpkgs-unstable.lib.genAttrs' gatewayHosts (name: {
        name = "openclaw-config-validity-${name}";
        value =
          pkgs.runCommandLocal "openclaw-config-validity-${name}"
            {
              nativeBuildInputs = [ self.nixosConfigurations.${name}.config.services.openclaw-gateway.package ];
            }
            ''
              export HOME="$TMPDIR/home"
              export OPENCLAW_STATE_DIR="$TMPDIR/state"
              export OPENCLAW_CONFIG_PATH=${
                self.nixosConfigurations.${name}.config.environment.etc."openclaw/openclaw.json".source
              }
              mkdir -p "$HOME" "$OPENCLAW_STATE_DIR"
              openclaw config validate --json > $out
            '';
      });

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
            deployKey =
              let
                envKey = builtins.getEnv "DEPLOY_KEY";
              in
              # Fallback is the fleet deploy key. ~/.ssh/deploy-key is the node tunnel secret and
              # must not be the credential that addresses the fleet.
              if envKey != "" then envKey else "~/.ssh/nixfiles-deploy-key";
          in
          {
            hostname =
              hostConfig.config.my.topology.hosts.${name}.wireguardIpv4
                or hostConfig.config.my.topology.hosts.${name}.wireguardIpv4;
            profiles.system = {
              user = "root";
              sshUser = "root";
              sshOpts = [
                "-i"
                deployKey
              ];
              path = inputs.deploy-rs.lib.${system}.activate.nixos hostConfig;
            };
          }
        ) self.nixosConfigurations;
      };

      nodTargets = {
        cloudflare = {
          targetHost = "api.cloudflare.com";
          role = "cloud";
          targetType = "agentless";
          tags = [
            "edge"
            "dns"
            "gitops"
          ];
          package =
            self.nixosConfigurations.cld-edge-01.config.my.features.system.networking.cloudflare.package;
        };

        hom-rt-01 = {
          targetHost = "10.10.10.1";
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
          targetHost = "10.10.10.20";
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
    };
}
