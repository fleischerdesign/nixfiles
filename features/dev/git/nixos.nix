# features/dev/git/nixos.nix — Generic Git + GitHub CLI Home-Manager & System Feature Module
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
    # System-level SOPS secrets & templates for GitHub CLI PAT. Gated on `enable`, so the system flag is
    # the switch it claims to be: with it off, no secret and no template is declared, instead of a
    # credential being provisioned by a feature the host did not turn on.
    (lib.mkIf (cfg.enable && config ? sops) {
      sops.secrets = builtins.listToAttrs (
        map (secretName: {
          name = "users/${secretName}/github_pat";
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
            content = mkHostsYaml cfg.ghUser config.sops.placeholder."users/${secretName}/github_pat";
          };
        }) cfg.secrets
      );
    })

    # Home Manager integration for all users: the per-user half is home.nix.
    {
      home-manager.sharedModules = [ ./home.nix ];
    }
  ];
}
