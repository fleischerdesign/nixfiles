# features/dev/git/default.nix — Git + GitHub CLI configuration
#
# Generisches Modul: deklarative Git-Config, gh-CLI und Credential-
# Helper für beliebig viele Accounts. SOPS-Templates deployen die
# gh-hosts.yml (OAuth-Token) via systemd-tmpfiles. Home-Manager setzt
# programs.git und programs.gh pro Account.
{
  config,
  lib,
  pkgs,
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
    enable = lib.mkEnableOption "Git, GitHub CLI, and credential helper";

    accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              systemUser = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Linux system user account to associate this Git configuration with.";
              };

              systemGroup = lib.mkOption {
                type = lib.types.str;
                default = "users";
                description = "Primary Linux group of the system user.";
              };

              userName = lib.mkOption {
                type = lib.types.str;
                description = "git config user.name.";
              };

              userEmail = lib.mkOption {
                type = lib.types.str;
                description = "git config user.email.";
              };

              ghUser = lib.mkOption {
                type = lib.types.str;
                description = "GitHub username for gh hosts.yml and API calls.";
              };

              sopsSecret = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = name;
                description = "SOPS secret name suffix for the GitHub PAT. Defaults to the account key.";
              };

              secretFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Direct path to secret file containing the GitHub PAT. Overrides sopsSecret if set.";
              };
            };
          }
        )
      );
      default = { };
      description = "Accounts to configure Git and gh for.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      accountNames = builtins.attrNames cfg.accounts;
      hasSops = config ? sops;

      sopsSecrets = lib.mkIf hasSops (
        builtins.listToAttrs (
          lib.concatMap (
            name:
            let
              acc = cfg.accounts.${name};
            in
            lib.optionals (acc.secretFile == null && acc.sopsSecret != null) [
              {
                name = "github_pat_${acc.sopsSecret}";
                value = { };
              }
            ]
          ) accountNames
        )
      );

      templates = lib.mkIf hasSops (
        builtins.listToAttrs (
          lib.concatMap (
            name:
            let
              acc = cfg.accounts.${name};
            in
            lib.optionals (acc.secretFile == null && acc.sopsSecret != null) [
              {
                name = "gh-hosts-${name}";
                value = {
                  owner = acc.systemUser;
                  group = acc.systemGroup;
                  content =
                    mkHostsYaml acc.ghUser config.sops.placeholder."github_pat_${acc.sopsSecret}";
                };
              }
            ]
          ) accountNames
        )
      );

      tmpfilesRules = lib.concatMap (
        name:
        let
          acc = cfg.accounts.${name};
          user = acc.systemUser;
          group = acc.systemGroup;
          userObj = config.users.users.${user} or null;
          home = if userObj != null then userObj.home else "/home/${user}";
          secretPath =
            if acc.secretFile != null then
              acc.secretFile
            else if hasSops && acc.sopsSecret != null then
              config.sops.templates."gh-hosts-${name}".path
            else
              null;
        in
        [
          "d ${home}/.config 0700 ${user} ${group} - -"
          "d ${home}/.config/gh 0700 ${user} ${group} - -"
        ]
        ++ lib.optionals (secretPath != null) [
          "L+ ${home}/.config/gh/hosts.yml 0600 ${user} ${group} - ${secretPath}"
        ]
      ) accountNames;

      homeManagerConfig = builtins.listToAttrs (
        map (name: {
          name = cfg.accounts.${name}.systemUser;
          value = {
            programs.git = {
              enable = true;
              settings = {
                user.name = cfg.accounts.${name}.userName;
                user.email = cfg.accounts.${name}.userEmail;
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

            home.packages = [ pkgs.gh ];
          };
        }) accountNames
      );
    in
    {
      sops.secrets = sopsSecrets;
      sops.templates = templates;
      systemd.tmpfiles.rules = tmpfilesRules;
      home-manager.users = homeManagerConfig;
    }
  );
}
