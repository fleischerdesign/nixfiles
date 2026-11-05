# remote-exec executor - a declared, least-privilege account and root for
# Gateway-authored build/test attempts. Enabling this module is the opt-in that
# makes a host eligible as an executor; the Gateway inventory is derived from
# exactly these declarations.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.remote-exec;
in
{
  options.my.features.services.remote-exec = {
    enable = lib.mkEnableOption "the remote build/test executor account";
    user = lib.mkOption {
      type = lib.types.str;
      default = "remote-exec";
      description = "Non-root account that owns attempts and runs their commands.";
    };
    root = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/remote-exec";
      description = "Attempt root, owned by the executor account.";
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Public keys allowed to log in as the executor account.";
    };
    authorizedKeyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Files with public keys allowed to log in as the executor account.";
    };
    runtimePath = lib.mkOption {
      type = lib.types.str;
      default = "/run/current-system/sw/bin";
      description = "PATH for supervised attempts; every required tool is a system package.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "remote-exec: the executor account must not be root";
      }
      {
        assertion = cfg.authorizedKeys != [ ] || cfg.authorizedKeyFiles != [ ];
        message = "remote-exec: declare at least one authorized key";
      }
      {
        assertion = cfg.root != "/" && lib.hasPrefix "/" cfg.root;
        message = "remote-exec: root must be an absolute, non-root path";
      }
    ];

    users.groups.${cfg.user} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.root;
      createHome = false;
      shell = pkgs.bash;
      # A user systemd manager must survive the SSH session that launched the
      # attempt; this is a declared prerequisite, not an assumed login state.
      linger = true;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      openssh.authorizedKeys.keyFiles = cfg.authorizedKeyFiles;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.root} 0700 ${cfg.user} ${cfg.user} -"
    ];

    environment.systemPackages = with pkgs; [
      python3
      rsync
      git
      bash
      coreutils
      openssh
    ];
  };
}
