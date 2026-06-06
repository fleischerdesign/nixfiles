{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.git;
in
{
  options.my.features.dev.git = {
    enable = lib.mkEnableOption "Git, GitHub CLI, and credential helper";

    users = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            username = lib.mkOption {
              type = lib.types.str;
              description = "System user name (for home-manager and SOPS secret owner)";
            };
            gitName = lib.mkOption {
              type = lib.types.str;
              description = "git config user.name";
            };
            gitEmail = lib.mkOption {
              type = lib.types.str;
              description = "git config user.email";
            };
          };
        }
      );
      default = [ ];
      description = "Users to configure Git and GitHub credentials for";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      git
      gh
    ];

    sops.secrets = builtins.listToAttrs (
      map (u: {
        name = "github_pat_${u.username}";
        value = {
          owner = u.username;
        };
      }) cfg.users
    );

    home-manager.users = builtins.listToAttrs (
      map (u: {
        name = u.username;
        value = {
          home.file.".gitconfig".text = ''
            [user]
              name = ${u.gitName}
              email = ${u.gitEmail}
            [credential "https://github.com"]
              helper = "!f() { echo username=x-access-token; echo password=$(cat /run/secrets/github_pat_${u.username}); }; f"
          '';

          programs.fish.interactiveShellInit = lib.mkAfter ''
            set -gx GITHUB_TOKEN (cat /run/secrets/github_pat_${u.username} 2>/dev/null)
          '';
        };
      }) cfg.users
    );
  };
}
