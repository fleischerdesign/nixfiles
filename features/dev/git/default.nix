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
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users to configure GitHub credentials for";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ git gh ];

    sops.secrets = builtins.listToAttrs (map (user: {
      name = "github_pat_${user}";
      value = { owner = user; };
    }) cfg.users);

    home-manager.users = builtins.listToAttrs (map (user: {
      name = user;
      value = {
        home.file.".gitconfig".text = ''
          [credential "https://github.com"]
            helper = "!f() { echo username=x-access-token; echo password=$(cat /run/secrets/github_pat_${user}); }; f"
        '';

        programs.fish.interactiveShellInit = lib.mkAfter ''
          set -gx GITHUB_TOKEN (cat /run/secrets/github_pat_${user} 2>/dev/null)
        '';
      };
    }) cfg.users);
  };
}
