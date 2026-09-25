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
        (import ./packages/overlays/fix/pi-coding-agent)
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
    in
    {
      formatter.${system} = pkgs.nixfmt-tree;

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
                gawk
                gnugrep
                gnutar
                gzip
                (python3.withPackages (ps: [ ps.pyyaml ]))
                findutils
              ];
              text = "exec ${./lib/updaters}/update-custom-packages.sh \"$@\"";
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
        pi-auth = (import ./features/dev/pi/lib/auth.nix { inherit pkgs; }).check;

        custom-package-updater =
          pkgs.runCommandLocal "custom-package-updater-check"
            {
              nativeBuildInputs = with pkgs; [
                bash
                python3
                jq
                gawk
              ];
            }
            ''
              python3 ${./lib/updaters/tests/test_github_source.py} ${./lib/updaters/update-custom-packages.sh}
              touch $out
            '';

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

        # Every rule this repository generates is an nftables match. The full parser cannot run here - it
        # wants netlink, which a build sandbox does not have - so this is the part that can be proven at
        # build time, and it is the part that would have caught the incident: a rule that names a command,
        # or carries a shell flag, is not a rule. What remains is syntax, and that is safe to defer,
        # because the firewall applies the whole ruleset in one nftables transaction: a malformed rule
        # fails loudly and leaves the previous ruleset in place instead of half-applying a new one.
        nftables-rules =
          let
            rulesOf = name: self.nixosConfigurations.${name}.config;
            generated = nixpkgs-unstable.lib.concatMapStringsSep "\n" (
              name:
              (rulesOf name).networking.firewall.extraInputRules
              + "\n"
              + (rulesOf name).networking.firewall.extraForwardRules
            ) hostNames;
          in
          pkgs.runCommandLocal "nftables-rules" { } ''
            cat > rules.txt <<'GENERATED'
            ${generated}
            GENERATED
            fail=0
            forbid() { if grep -qE -- "$1" rules.txt; then echo "violation: $2" >&2; fail=1; fi; }
            forbid '(^|[[:space:]])(iptables|ip6tables|nft)([[:space:]]|$)' "a rule names a command instead of a match"
            forbid '/bin/' "a rule contains a store path"
            forbid '(^|[[:space:]])-(A|I|D|F|X|N)([[:space:]]|$)' "a rule contains a shell flag"
            forbid -- '--comment' "a rule contains an iptables-only flag"
            forbid '(^|[[:space:]])-s[[:space:]]' "a rule uses -s instead of ip saddr"
            while read -r line; do
              [ -n "$line" ] || continue
              stripped=$(printf '%s' "$line" | sed 's/ comment .*$//')
              case "$stripped" in
                *accept|*drop|*reject|*return|*jump*) ;;
                *) echo "violation: rule without a verdict: $line" >&2; fail=1 ;;
              esac
            done < rules.txt
            [ "$fail" -eq 0 ] || exit 1
            echo 'ok: every generated rule is an nftables match with a verdict' > $out
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

        # The identity provider's blueprints only fail on the host: a model name without a dot, a
        # `!KeyOf` that points nowhere, a dependency on a blueprint that is not there, or a person who
        # is declared instead of seeded. The apply there proves the same files, but a deploy is too late
        # for a typo. This reads the exact compiled directory the server ships, so the check and the
        # apply consume identical bytes. The rules are documented in docs/identity.md §11 and enforced
        # by features/services/authentik/lib/blueprints-check.py.
        authentik-blueprints =
          let
            blueprintLib = import ./features/services/authentik/lib/blueprint.nix {
              lib = nixpkgs-unstable.lib;
            };
            directories = map (
              name: self.nixosConfigurations.${name}.config.my.features.services.authentik.server.blueprintsDir
            ) blueprintHosts;
            ownerLabel = "${blueprintLib.ownerLabelName}=${blueprintLib.ownerLabelValue}";
          in
          pkgs.runCommandLocal "authentik-blueprints-check"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
              ];
            }
            ''
              python3 ${./features/services/authentik/lib/blueprints-check.py} \
                --owner-label ${nixpkgs-unstable.lib.escapeShellArg ownerLabel} \
                ${
                  nixpkgs-unstable.lib.concatStringsSep " " (
                    map (directory: nixpkgs-unstable.lib.escapeShellArg "${directory}") directories
                  )
                } \
                > $out
            '';

        # The apply and the drift report are Python embedded in the module and executed only on the host;
        # a syntax error in either would otherwise be found by a deploy, which is a fleet-wide failure.
        # This compiles both with the same interpreter the host runs, so a pull request finds it instead.
        authentik-scripts =
          let
            units = [
              "authentik-blueprints-apply"
              "authentik-drift-report"
            ];
            scriptOf =
              name: unit:
              builtins.substring 5 1000000
                self.nixosConfigurations.${name}.config.systemd.services.${unit}.serviceConfig.StandardInput;
            scripts = nixpkgs-unstable.lib.unique (
              nixpkgs-unstable.lib.concatMap (name: map (scriptOf name) units) blueprintHosts
            );
          in
          pkgs.runCommandLocal "authentik-scripts-check"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              for script in ${nixpkgs-unstable.lib.concatStringsSep " " scripts}; do
                python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="out.pyc", doraise=True)' "$script"
              done
              echo "ok: ${toString (nixpkgs-unstable.lib.length scripts)} embedded authentik script(s) compile" > $out
            '';

        # The portal is built, not fetched, and its catalogue is a build input: the artifact the portal
        # host runs has to carry what its pages were rendered from. lib/checks/vyrx-portal.nix states the
        # claim and measures it on the artifact, where the consumer sees it.
        vyrx-portal = import ./lib/checks/vyrx-portal.nix {
          inherit pkgs self hostNames;
          lib = nixpkgs-unstable.lib;
        };
      }
      //
        nixpkgs-unstable.lib.mapAttrs'
          (name: drv: nixpkgs-unstable.lib.nameValuePair "pi-plugin-${name}" drv)
          (import ./features/dev/pi/lib/plugins.nix {
            inherit pkgs;
            lib = nixpkgs-unstable.lib;
          }).derivations;

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
