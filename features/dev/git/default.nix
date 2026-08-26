# features/dev/git/default.nix — Generic Git + GitHub CLI Home-Manager & System Feature Module
#
# Architecture & Guidelines:
# - User-Scoped Feature: Registered via `home-manager.sharedModules` so users (philipp, hermes, external accounts)
#   can activate Git + gh independently via `my.features.dev.git.enable = true`.
# - System Secrets: Generates SOPS secret & template `gh-hosts-<secretName>` for GitHub PAT decryption at system level.
# - Agnostic & Generic: Zero hardcoded usernames/hostnames. Reusable across NixOS & Home Manager.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.git;

  mkHostsYaml = ghUser: placeholder: ''
    github.com:
      oauth_token: ${placeholder}
      user: ${ghUser}
  '';
in
{
  options.my.features.dev.git = {
    enable = lib.mkEnableOption "system-wide Git & GitHub CLI secrets template";

    secrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "philipp" ];
      description = "List of SOPS secret names (github_pat_<name>) to decrypt for gh-hosts templates.";
    };

    ghUser = lib.mkOption {
      type = lib.types.str;
      default = "fleischerdesign";
      description = "Default GitHub username for gh hosts.yml template.";
    };
  };

  config = lib.mkMerge [
    # System-level SOPS secrets & templates for GitHub CLI PAT
    (lib.mkIf (config ? sops) {
      sops.secrets = builtins.listToAttrs (
        map (secretName: {
          name = "github_pat_${secretName}";
          value = { };
        }) cfg.secrets
      );

      sops.templates = builtins.listToAttrs (
        map (secretName: {
          name = "gh-hosts-${secretName}";
          value = {
            owner = config.my.user.primary or "root";
            group = "users";
            mode = "0440";
            content = mkHostsYaml cfg.ghUser config.sops.placeholder."github_pat_${secretName}";
          };
        }) cfg.secrets
      );
    })

    # Home Manager integration for all users
    {
      home-manager.sharedModules = [
        (
          {
            config,
            lib,
            osConfig ? { },
            ...
          }:
          let
            userCfg = config.my.features.dev.git;
            primaryUser = osConfig.my.user or { };
          in
          {
            options.my.features.dev.git = {
              enable = lib.mkEnableOption "Git and GitHub CLI for this Home Manager user";

              userName = lib.mkOption {
                type = lib.types.str;
                default = primaryUser.fullName or "Philipp Fleischer";
                description = "git config user.name";
              };

              userEmail = lib.mkOption {
                type = lib.types.str;
                default = primaryUser.email or "philipp@fleischer.design";
                description = "git config user.email";
              };

              ghUser = lib.mkOption {
                type = lib.types.str;
                default = "fleischerdesign";
                description = "GitHub username for gh hosts.yml";
              };

              sopsSecret = lib.mkOption {
                type = lib.types.str;
                default = "philipp";
                description = "SOPS secret name for gh PAT template (github_pat_<sopsSecret>)";
              };
            };

            config = lib.mkIf userCfg.enable {
              programs.git = {
                enable = true;
                ignores = [ ".pi/" ];
                settings = {
                  user.name = userCfg.userName;
                  user.email = userCfg.userEmail;
                };
              };

              programs.gh = {
                enable = true;
                gitCredentialHelper.enable = true;
                settings = {
                  git_protocol = "https";
                  editor = "";
                  prompt = "enabled";
                };
              };

              home.file = {
                ".config/gh/hosts.yml" =
                  lib.mkIf (osConfig ? sops && osConfig.sops.templates ? "gh-hosts-${userCfg.sopsSecret}")
                    {
                      source =
                        config.lib.file.mkOutOfStoreSymlink
                          osConfig.sops.templates."gh-hosts-${userCfg.sopsSecret}".path;
                    };
              };
            };
          }
        )
      ];
    }
  ];
}
