# Nautilus integration is a graphical preference, not part of the rclone engine.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.system.rclone;
  bookmarks = "${config.xdg.configHome}/gtk-3.0/bookmarks";
in
{
  home.activation.rcloneBookmarks = lib.mkIf cfg.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg "${config.xdg.configHome}/gtk-3.0"}
      run ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg bookmarks}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: mount:
          let
            uri = "file://${mount.mountPoint}";
            label = if name == "gdrive" then "Google Drive" else name;
          in
          ''
            if ! ${pkgs.gawk}/bin/awk -v uri=${lib.escapeShellArg uri} '
              $1 == uri { found = 1 } END { exit !found }
            ' ${lib.escapeShellArg bookmarks}; then
              run ${pkgs.bash}/bin/bash -c 'printf "%s\n" "$1" >> "$2"' -- \
                ${lib.escapeShellArg "${uri} ${label}"} ${lib.escapeShellArg bookmarks}
            fi
          ''
        ) cfg.mounts
      )}
    ''
  );
}
