# features/system/user/default.nix
# Declarative multi-user identity module with dynamic metadata lookup.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  userDir = ../../../user;
  discoveredUserNames =
    if builtins.pathExists userDir then
      lib.filter (name: builtins.pathExists (userDir + "/${name}/metadata.nix")) (
        builtins.attrNames (builtins.readDir userDir)
      )
    else
      [ ];

  allUserMeta = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = import (userDir + "/${name}/metadata.nix");
    }) discoveredUserNames
  );

  humanUserNames = lib.filter (n: (allUserMeta.${n}.type or "human") == "human") discoveredUserNames;

  defaultPrimary =
    if humanUserNames != [ ] then
      lib.head humanUserNames
    else if discoveredUserNames != [ ] then
      lib.head discoveredUserNames
    else
      "root";
in
{
  options.my.user = {
    usersDir = lib.mkOption {
      type = lib.types.path;
      default = ../../../user;
      description = "Path to directory containing user metadata subdirectories.";
    };

    primary = lib.mkOption {
      type = lib.types.str;
      default = defaultPrimary;
      description = "Primary user account name.";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = config.my.user.primary;
      description = "Alias for primary user. Deprecated — use my.user.primary.";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = (allUserMeta.${config.my.user.primary} or { }).fullName or config.my.user.primary;
      description = "Full display name of the primary user.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = (allUserMeta.${config.my.user.primary} or { }).email or "";
      description = "Primary email address of the user.";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "networkmanager"
        "wheel"
      ];
      description = "Extra groups assigned to the primary user.";
    };

    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = (allUserMeta.${config.my.user.primary} or { }).sshKeys or [ ];
      description = "Authorized SSH public keys for the primary user.";
    };

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to SOPS-managed hashedPassword file.";
    };

    sopsAgeKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/home/${config.my.user.primary}/.config/sops/age/keys.txt";
      description = "Path to the user's Age key file for SOPS CLI.";
    };
  };

  config = lib.mkMerge (
    let
      cfg = config.my.user;
    in
    [
      (lib.mkIf (config ? sops) {
        sops.secrets."users/${cfg.primary}/password".neededForUsers = lib.mkDefault true;
        my.user.hashedPasswordFile = lib.mkDefault config.sops.secrets."users/${cfg.primary}/password".path;
      })
      {
        environment.sessionVariables = lib.mkIf (cfg.sopsAgeKeyFile != null) {
          SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
        };

        users.users.${cfg.primary} = {
          isNormalUser = true;
          description = cfg.fullName;
          inherit (cfg) extraGroups;
          openssh.authorizedKeys.keys = cfg.sshKeys;
          hashedPasswordFile = lib.mkIf (cfg.hashedPasswordFile != null) cfg.hashedPasswordFile;
        };
      }
    ]
    ++ (lib.mapAttrsToList (
      name: meta:
      let
        userType = meta.type or "human";
      in
      lib.mkIf (name != cfg.primary) {
        users.users.${name} = lib.mkMerge [
          {
            isNormalUser = userType == "human";
            isSystemUser = userType != "human";
            description = meta.fullName or name;
            openssh.authorizedKeys.keys = meta.sshKeys or [ ];
            extraGroups = meta.extraGroups or [ ];
          }
          (lib.mkIf (userType != "human") {
            home = lib.mkDefault "/home/${name}";
            createHome = lib.mkDefault true;
            shell = lib.mkDefault pkgs.bash;
            group = lib.mkDefault name;
          })
          (lib.optionalAttrs (meta ? shell) { inherit (meta) shell; })
        ];
      }
    ) allUserMeta)
    ++ (lib.mapAttrsToList (
      name: meta:
      lib.mkIf ((meta.type or "human") != "human") {
        users.groups.${name} = { };
      }
    ) (lib.filterAttrs (_: m: (m.type or "human") != "human") allUserMeta))
  );
}
