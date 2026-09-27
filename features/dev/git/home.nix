# features/dev/git/home.nix - the per-user half of the Git/GitHub CLI feature.
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
