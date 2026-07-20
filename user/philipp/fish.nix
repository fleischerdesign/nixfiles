# user/philipp/fish.nix
# Declarative Fish shell configuration, aliases, and custom helper functions.
{
  lib,
  hostname,
  osConfig,
  ...
}:

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
          if test (count $argv) -eq 0
              echo "Usage:   tpl <template-name> [target-directory]"
              echo "Example: tpl c my-app"
              echo "Source:  github:fleischerdesign/nix-<name>-template"
              return 1
          end

          set -l tpl_name $argv[1]
          set -l repo_url "github:fleischerdesign/nix-$tpl_name-template"

          # Optional target directory
          if test (count $argv) -ge 2
              set -l target_dir $argv[2]
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

          echo "🚀 Initializing template from $repo_url..."
          if nix flake init -t $repo_url
              echo "✅ Template successfully initialized in $(pwd)."
              if type -q direnv
                  echo "🔓 Allowing direnv..."
                  direnv allow
              end
          else
              echo "❌ Error: Failed to fetch template from $repo_url"
              return 1
          end
        '';
      };
    };
  };
}
