# Verify the actual workstation session and its generated shell configuration.
{
  pkgs,
  lib,
  self,
  ...
}:
let
  cfg = self.nixosConfigurations.hom-wrk-01.config;
  user = cfg.home-manager.users.${cfg.my.user.primary};
  startup = user.programs.niri.settings.spawn-at-startup;
  shell = lib.getExe user.programs.noctalia.package;
  niriConfig = user.xdg.configFile.niri-config.source;
  noctaliaConfig = user.xdg.configFile."noctalia/config.toml".source;
  environment = cfg.my.desktop.environments;
in
if
  cfg.my.features.desktop.niri.enable
  && cfg.my.features.desktop.noctalia.enable
  && environment.niri
  && builtins.length (lib.attrNames (lib.filterAttrs (_: enabled: enabled) environment)) == 1
  && cfg.services.greetd.enable
  && cfg.services.greetd.settings.default_session.user == cfg.my.user.primary
  &&
    cfg.services.greetd.settings.default_session.command
    == "${cfg.programs.niri.package}/bin/niri-session"
  && !cfg.services.displayManager.gdm.enable
  && !cfg.services.desktopManager.gnome.enable
  && user.programs.noctalia.enable
  && !user.programs.noctalia.systemd.enable
  && user.programs.noctalia.settings.shell.polkit_agent
  && user.programs.noctalia.settings.backdrop.enabled
  && startup == [ { argv = [ shell ]; } ]
  && !(builtins.elem 7391 cfg.networking.firewall.allowedTCPPorts)
  && cfg.networking.networkmanager.enable
  && cfg.hardware.bluetooth.enable
  && cfg.services.upower.enable
  && cfg.services.power-profiles-daemon.enable
then
  pkgs.runCommandLocal "niri-noctalia-check"
    {
      nativeBuildInputs = [ pkgs.gnugrep ];
    }
    ''
      fail=0
      if ! ${lib.getExe cfg.programs.niri.package} validate -c ${niriConfig}; then
        echo 'niri-noctalia: generated Niri config is invalid' >&2
        fail=1
      fi
      if ! ${shell} config validate ${noctaliaConfig} > validator.log 2>&1; then
        cat validator.log >&2
        echo 'niri-noctalia: generated Noctalia config is invalid' >&2
        fail=1
      fi
      if grep -E '(^|[[:space:]])WARN([[:space:]]|$)' validator.log >&2; then
        echo 'niri-noctalia: Noctalia ignored or migrated a declared setting' >&2
        fail=1
      fi
      if ! grep -F 'spawn-at-startup "${shell}"' ${niriConfig} >/dev/null; then
        echo 'niri-noctalia: generated Niri config does not start the selected shell' >&2
        fail=1
      fi
      for expected in \
        'honor-xdg-activation-with-invalid-serial' \
        'match namespace="^noctalia-backdrop"' \
        'place-within-backdrop true' \
        'match namespace="^noctalia-window-switcher$"' \
        'background-effect' \
        'xray false' \
        'open-floating true' \
        'Mod+Shift+Comma' \
        'Alt+Tab'; do
        if ! grep -F -- "$expected" ${niriConfig} >/dev/null; then
          echo "niri-noctalia: generated Niri config is missing $expected" >&2
          fail=1
        fi
      done
      if grep -Ei 'axis-shell|\.config/axis|org\.axis' ${niriConfig} >&2; then
        echo 'niri-noctalia: generated Niri config contains Axis' >&2
        fail=1
      fi
      [ "$fail" -eq 0 ] || exit 1
      echo 'Niri session and generated Niri/Noctalia configurations validated' > "$out"
    ''
else
  throw "niri-noctalia: workstation session, single shell startup, required services or closed Axis port failed"
