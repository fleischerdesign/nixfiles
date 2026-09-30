{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.my.features.system.rclone;
  absolutePath = lib.types.strMatching "/[^\n]+";
  exec = args: builtins.replaceStrings [ "%" ] [ "%%" ] (lib.escapeShellArgs args);
  mountType = lib.types.submodule (
    { name, config, ... }:
    let
      mount = config;
    in
    {
      options = {
        remote = lib.mkOption {
          type = lib.types.str;
          description = "Named rclone remote and path, such as drive: or server:/.";
        };
        configFile = lib.mkOption {
          type = absolutePath;
          description = "Runtime configuration path; writable when the backend refreshes OAuth tokens.";
        };
        requiredFiles = lib.mkOption {
          type = lib.types.listOf absolutePath;
          default = [ ];
          description = "Additional credential or trust files required before starting.";
        };
        mountPoint = lib.mkOption {
          type = absolutePath;
          default = "${cfg.mountRoot}/${name}";
          description = "Empty, user-owned directory used as the mount point.";
        };
        readOnly = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Reject writes through this mount.";
        };
        cacheMode = lib.mkOption {
          type = lib.types.enum [
            "off"
            "writes"
            "full"
          ];
          default = if mount.readOnly then "off" else "writes";
          description = "VFS caching mode; no mode mirrors the complete remote.";
        };
        cacheMaxSize = lib.mkOption {
          type = lib.types.str;
          default = "2Gi";
          description = "Soft cache size limit; open and pending files can exceed it.";
        };
        cacheMaxAge = lib.mkOption {
          type = lib.types.str;
          default = "24h";
          description = "Maximum unused cache age; pending uploads are retained.";
        };
        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional non-secret backend arguments; do not override mount ownership or safety flags.";
        };
      };
    }
  );
in
{
  options.my.features.system.rclone = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = osConfig.my.features.system.rclone.enable or false;
      description = "Enable this user's declared rclone mounts.";
    };
    package = lib.mkPackageOption pkgs "rclone" { };
    mountRoot = lib.mkOption {
      type = absolutePath;
      default = "${config.home.homeDirectory}/mounts";
      description = "Default parent of the named mount points.";
    };
    sessionTarget = lib.mkOption {
      type = lib.types.str;
      default = "default.target";
      description = "User target which starts and owns the mount services.";
    };
    mounts = lib.mkOption {
      type = lib.types.attrsOf mountType;
      default = { };
      description = "Provider-independent named remote mounts.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = osConfig.my.features.system.rclone.enable or false;
        message = "User rclone mounts require the host's rclone/FUSE feature.";
      }
      {
        assertion = lib.all (name: builtins.match "[a-z0-9][a-z0-9_-]*" name != null) (
          lib.attrNames cfg.mounts
        );
        message = "rclone mount names must be lowercase letters, digits, underscores or hyphens.";
      }
      {
        assertion =
          let
            paths = map (mount: mount.mountPoint) (lib.attrValues cfg.mounts);
          in
          builtins.length paths == builtins.length (lib.unique paths);
        message = "rclone mount points must be unique.";
      }
    ];
    home.packages = [ cfg.package ];
    systemd.user.services = lib.mapAttrs' (name: mount: {
      name = "rclone-${name}";
      value = {
        Unit = {
          Description = "Rclone remote mount: ${name}";
          After = [ cfg.sessionTarget ];
          PartOf = [ cfg.sessionTarget ];
          ConditionPathExists = [ mount.configFile ] ++ mount.requiredFiles;
          StartLimitIntervalSec = 0;
        };
        Service = {
          Type = "notify";
          NotifyAccess = "main";
          UMask = "0077";
          Environment = [
            "PATH=/run/wrappers/bin:${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.fuse3
              ]
            }"
          ];
          ExecStartPre = exec [
            "${pkgs.coreutils}/bin/mkdir"
            "-p"
            "--"
            mount.mountPoint
          ];
          ExecStart = exec (
            [
              (lib.getExe cfg.package)
              "mount"
              mount.remote
              mount.mountPoint
              "--config"
              mount.configFile
              "--cache-dir"
              "${config.xdg.cacheHome}/rclone/${name}"
              "--vfs-cache-mode"
              mount.cacheMode
              "--vfs-cache-max-size"
              mount.cacheMaxSize
              "--vfs-cache-max-age"
              mount.cacheMaxAge
              "--umask"
              "077"
              "--log-level"
              "NOTICE"
              "--contimeout"
              "10s"
              "--timeout"
              "30s"
            ]
            ++ lib.optional mount.readOnly "--read-only"
            ++ mount.extraArgs
          );
          # Foreground rclone handles SIGTERM and unmounts. A busy/stale mount
          # requires operator attention; never unmount an unrelated filesystem.
          Restart = "on-failure";
          RestartSec = 30;
          TimeoutStartSec = 60;
          TimeoutStopSec = 120;
        };
        Install.WantedBy = [ cfg.sessionTarget ];
      };
    }) cfg.mounts;
  };
}
