# features/system/user/default.nix
# Declarative user identity module for system users with dynamic metadata lookup.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.user;
  userDir = ../../../user;
  discoveredUsers =
    if builtins.pathExists userDir then
      lib.filter (
        name: builtins.pathExists (userDir + "/${name}/metadata.nix")
      ) (builtins.attrNames (builtins.readDir userDir))
    else
      [ ];
  defaultUserName = if discoveredUsers != [ ] then lib.head discoveredUsers else "philipp";

  userMetaPath = ../../../user + "/${cfg.name}/metadata.nix";
  userMeta = if builtins.pathExists userMetaPath then import userMetaPath else { };
in
{
  options.my.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = defaultUserName;
      description = "Primary user account name.";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = userMeta.fullName or cfg.name;
      description = "Full display name of the primary user.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = userMeta.email or "";
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
      default = userMeta.sshKeys or [ ];
      description = "Authorized SSH public keys for the primary user.";
    };

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to SOPS-managed hashedPassword file for zero-trust declarative user auth.";
    };

    sopsAgeKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/home/${cfg.name}/.config/sops/age/keys.txt";
      description = "Path to the user's Age key file for SOPS CLI decryption.";
    };
  };

  config = {
    sops.secrets."users/${cfg.name}/password" = {
      neededForUsers = true;
    };

    my.user.hashedPasswordFile = lib.mkDefault config.sops.secrets."users/${cfg.name}/password".path;

    environment.sessionVariables = lib.mkIf (cfg.sopsAgeKeyFile != null) {
      SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
    };

    users.users.${cfg.name} = {
      isNormalUser = true;
      description = cfg.fullName;
      inherit (cfg) extraGroups;
      openssh.authorizedKeys.keys = cfg.sshKeys;
      hashedPasswordFile = lib.mkIf (cfg.hashedPasswordFile != null) cfg.hashedPasswordFile;
    };
  };
}
