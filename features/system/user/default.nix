# features/system/user/default.nix
# Declarative user identity module for the primary system user.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.user;
  userMeta = import ../../../user/philipp/metadata.nix;
in
{
  options.my.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = userMeta.username;
      description = "Primary user account name.";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = userMeta.fullName;
      description = "Full display name of the primary user.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = userMeta.email;
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
      default = userMeta.sshKeys;
      description = "Authorized SSH public keys for the primary user.";
    };

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to SOPS-managed hashedPassword file for zero-trust declarative user auth.";
    };
  };

  config = {
    sops.secrets."users/${cfg.name}/password" = {
      neededForUsers = true;
    };

    my.user.hashedPasswordFile = lib.mkDefault config.sops.secrets."users/${cfg.name}/password".path;

    users.users.${cfg.name} = {
      isNormalUser = true;
      description = cfg.fullName;
      inherit (cfg) extraGroups;
      openssh.authorizedKeys.keys = cfg.sshKeys;
      hashedPasswordFile = lib.mkIf (cfg.hashedPasswordFile != null) cfg.hashedPasswordFile;
    };
  };
}
