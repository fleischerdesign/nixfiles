# user/philipp/fish.nix
# Declarative Fish shell configuration, aliases, and custom helper functions.
{
  lib,
  hostname,
  osConfig,
  ...
}:

let
  # Decodes to the literal fish-source text "\${system}" (backslash dollar brace system closing
  # brace). Built via concatenation so this module string never contains an active "${" that Nix
  # would interpolate at config-build time. Inside tpl's double-quoted echo, fish then turns "\$"
  # into "$", so the generated flake.nix ends up with the valid per-system interpolation "${system}".
  sysRef = "\\" + "$" + "{system}";
in

{
  programs.fish = {
    enable = true;

    shellAliases = {
      c = "codium";
    }
    // lib.optionalAttrs (hostname != "rollins") {
      hermes = "ssh -t ${osConfig.my.user.name}@${osConfig.my.features.system.networking.topology.hosts.rollins.tailscaleIp} hermes";
    };

    functions = {
      tpl = {
        description = "Initialize a Nix development project from github:fleischerdesign/nix-<name>-template";
        body = ''
          set -l copy_mode false
          set -l args

          for arg in $argv
              if test "$arg" = "-c" -o "$arg" = "--copy"
                  set copy_mode true
              else
                  set -a args $arg
              end
          end

          if test (count $args) -eq 0
              echo "Usage:   tpl [-c|--copy] <template-name> [target-directory]"
              echo "Example: tpl rust my-app         # Idiomatic Flake Input (Clean, input-only)"
              echo "Example: tpl -c rust my-app      # Copy Mode (Copies template files locally)"

              set -l tpls (curl -s "https://api.github.com/users/fleischerdesign/repos?per_page=100" | string match -r -g '"name": "nix-([^"]+)-template"' | sort -u)
              if test -n "$tpls"
                  echo "Available: "(string join ", " $tpls)
              end
              echo "Source:  github:fleischerdesign/nix-<name>-template"
              return 1
          end

          set -l tpl_name $args[1]
          set -l repo_url "github:fleischerdesign/nix-$tpl_name-template"

          # Optional target directory
          if test (count $args) -ge 2
              set -l target_dir $args[2]
              if not test -d $target_dir
                  echo "📁 Creating directory $target_dir..."
                  mkdir -p $target_dir
              end
              cd $target_dir
          end

          # Guard: prevent overwriting existing flake
          if test -f flake.nix
              echo "❌ Error: A flake.nix file already exists in $(pwd)."
              return 1
          end

          if test "$copy_mode" = true
              echo "🚀 Initializing template via 'nix flake init' (Copy Mode)..."
              if nix flake init -t $repo_url
                  echo "✅ Template files successfully copied into $(pwd)."
                  if type -q direnv
                      echo "🔓 Allowing direnv..."
                      direnv allow
                  end
              else
                  echo "❌ Error: Failed to fetch template from $repo_url"
                  return 1
              end
          else
              echo "🚀 Creating clean idiomatic Flake setup from $repo_url..."
              echo "{
  description = \"$tpl_name application\";

  inputs = {
    nixpkgs.url = \"github:NixOS/nixpkgs/nixos-26.05\";
    flake-utils.url = \"github:numtide/flake-utils\";
    nix-$tpl_name.url = \"$repo_url\";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-$tpl_name,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${sysRef};
      in
      {
        devShells = {
          default = nix-$tpl_name.devShells.${sysRef}.default;
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}" > flake.nix

              echo "use flake" > .envrc

              echo "✅ Idiomatic Flake setup created in $(pwd)."
              if type -q direnv
                  echo "🔓 Allowing direnv..."
                  direnv allow
              end
          end
        '';
      };
    };
  };
}
