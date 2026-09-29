# Community template readiness. Community template files are downloaded after the first
# theme render, so a fresh account can ask for a template before its files exist. This
# unit states readiness once: it reads the selected ids from the shell's own settings and
# fails when they are not cached, and systemd retries it a bounded number of times. When
# the bound is reached the unit fails loudly.
#
# This is a module of its own rather than part of home.nix: a module that both defines
# `my.features.desktop.noctalia.settings` and reads it back in a condition is a cycle.
{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
  niriEnabled = osConfig.my.features.desktop.niri.enable or false;
  noctalia = lib.getExe config.programs.noctalia.package;
  communityIds = config.my.features.desktop.noctalia.settings.theme.templates.community_ids or [ ];

  applyCommunityTemplates = pkgs.writeShellApplication {
    name = "noctalia-apply-community-templates";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      cache=${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/community-templates"}
      ids=${lib.escapeShellArg (builtins.toJSON communityIds)}

      if [ ! -s "$cache/catalog.json" ]; then
        echo 'Noctalia community template catalog is not cached yet' >&2
        exit 1
      fi

      files=$(jq -e -r --argjson ids "$ids" '
        [.[] | select(.name as $name | $ids | index($name))] as $selected
        | if ($selected | length) != ($ids | length) then
            error("a selected Noctalia community template is missing from the catalog")
          else
            $selected[] | .name as $name | .files[].name | "\($name)/\(.)"
          end
      ' "$cache/catalog.json")

      while IFS= read -r file; do
        if [ ! -s "$cache/$file" ]; then
          echo "Noctalia community template file is not cached yet: $file" >&2
          exit 1
        fi
      done <<< "$files"

      ${noctalia} msg templates-apply
    '';
  };
in
{
  config = lib.mkIf (cfg.enable && niriEnabled && communityIds != [ ]) {
    systemd.user.services.noctalia-community-templates = {
      Unit = {
        Description = "Apply Noctalia community templates once their cache is complete";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        StartLimitBurst = 30;
        StartLimitIntervalSec = 120;
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe applyCommunityTemplates;
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
