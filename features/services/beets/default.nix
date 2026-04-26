{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.beets;
in
{
  options.my.features.services.beets = {
    enable = lib.mkEnableOption "Beets Music Tagger";
    musicDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/data/storage/music";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.beets ];

    # Global Beets Configuration
    environment.etc."beets/config.yaml".text = ''
      directory: ${cfg.musicDirectory}
      library: /var/lib/beets/musiclibrary.db
      statefile: /var/lib/beets/state.pickle
      import:
        write: true
        copy: false
        move: false
        resume: ask
        incremental: true
        quiet_fallback: asis
        timid: false
        log: /var/lib/beets/import.log
      plugins: [ mbsync, lastgenre, lyrics, scrub, info ]
      lastgenre:
        auto: true
        source: album
      lyrics:
        auto: true
    '';

    # Create library directory with access for media group
    systemd.tmpfiles.rules = [
      "d /var/lib/beets 2775 root media -"
    ];

    # Automation script provided by the beets feature
    environment.etc."beets/lidarr-automator.sh" = {
      mode = "0755";
      text = ''
        #!${pkgs.bash}/bin/bash
        # Triggered by Lidarr: lidarr_eventtype, lidarr_album_path
        if [ "$lidarr_eventtype" == "Download" ] || [ "$lidarr_eventtype" == "AlbumDownload" ]; then
          echo "[$(date)] Beets: Tagging $lidarr_album_path" >> /var/lib/beets/import.log
          ${pkgs.beets}/bin/beet -c /etc/beets/config.yaml import -q "$lidarr_album_path" >> /var/lib/beets/import.log 2>&1
        fi
      '';
    };
  };
}