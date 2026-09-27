# features/system/user/nixos.nix
# Declarative multi-user identity module with metadata lookup from a single discovery source.
{
  config,
  lib,
  usersLib,
  pkgs,
  ...
}:
let

  # Discovery reads the configured directory, not a path spelled in this file: `usersDir` is
  # the one knob, and changing it changes who exists. There is no alphabetical fallback for the
  # primary user - every host assigns its primary explicitly (decision D11), and an unknown name
  # fails the build instead of quietly becoming somebody else.
  discoveredUserNames = usersLib.discoverNames config.my.user.usersDir;
  allUserMeta = usersLib.loadMeta config.my.user.usersDir discoveredUserNames;
in
{
  options.my.user = {
    usersDir = lib.mkOption {
      type = lib.types.path;
      default = ../../../user;
      description = "Directory of user metadata subdirectories; the single discovery source.";
    };

    primary = lib.mkOption {
      type = lib.types.str;
      description = "Primary user account name, assigned explicitly per host.";
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

    profiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "core" ];
      description = "Active Home-Manager atomic profiles for primary user (e.g. core, graphical).";
    };
  };

  config = lib.mkMerge (
    let
      cfg = config.my.user;
      # Accounts beyond the primary, keyed by discovered name. Discovery feeds VALUES under the
      # static `users.users` path - never the definition structure itself: the module system
      # enumerates definition paths while merging, so a discovery-derived list spine at the top
      # level feeds back into the discovery it reads from (measured: infinite recursion).
      otherUsers = removeAttrs allUserMeta [ cfg.primary ];
    in
    [
      {
        assertions = [
          {
            assertion = builtins.elem cfg.primary discoveredUserNames;
            message = "my.user.primary '${cfg.primary}' on ${config.networking.hostName} names no user in ${toString cfg.usersDir}";
          }
        ];
      }
      (lib.mkIf (config ? sops) {
        sops.secrets."users/${cfg.primary}/password".neededForUsers = lib.mkDefault true;
        my.user.hashedPasswordFile = lib.mkDefault config.sops.secrets."users/${cfg.primary}/password".path;
      })
      {
        environment.sessionVariables = lib.mkIf (cfg.sopsAgeKeyFile != null) {
          SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
        };

        systemd.tmpfiles.rules = lib.concatMap (name: [
          "d /nix/var/nix/profiles/per-user/${name} 0755 ${name} users - -"
          "d /home/${name} 0700 ${name} users - -"
          "d /home/${name}/.local 0755 ${name} users - -"
        ]) discoveredUserNames;

        users.users =
          let
            others = removeAttrs allUserMeta [ cfg.primary ];
            mkOther =
              name: meta:
              let
                userType = meta.type or "human";
              in
              lib.mkMerge [
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
          in
          {
            ${cfg.primary} = {
              isNormalUser = true;
              description = cfg.fullName;
              inherit (cfg) extraGroups;
              openssh.authorizedKeys.keys = cfg.sshKeys;
              hashedPasswordFile = lib.mkIf (cfg.hashedPasswordFile != null) cfg.hashedPasswordFile;
            };
          }
          // lib.mapAttrs mkOther others;

        users.groups = lib.mapAttrs (_: _: { }) (
          lib.filterAttrs (_: m: (m.type or "human") != "human") otherUsers
        );
      }
    ]
  );
}
