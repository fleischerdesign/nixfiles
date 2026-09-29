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
  ghosttyConfig = user.xdg.configFile."ghostty/config".source;
  qt6ctConfig = user.xdg.configFile."qt6ct/qt6ct.conf".source;
  configLink = user.xdg.configFile."noctalia/config.toml".source;
  configTemplate = user.sops.templates."noctalia-config.toml";
  noctaliaSettings = user.my.features.desktop.noctalia.settings;
  environment = cfg.my.desktop.environments;

  # The template selection is derived from the integrations, so the expected sets are
  # spelled out here once and must match what the modules produce.
  expectedBuiltinIds = builtins.sort builtins.lessThan [
    "btop"
    "ghostty"
    "gtk3"
    "gtk4"
    "kcolorscheme"
    "niri"
    "qt"
  ];
  expectedCommunityIds = builtins.sort builtins.lessThan [
    "obsidian"
    "vscode"
  ];
  expectedPlugins = builtins.sort builtins.lessThan [
    "andrewdems/printers"
    "icefish/phone-operate"
    "noctalia/bitwarden"
    "pozzoo/hassio"
    "weinguyen/opencode-companion"
  ];

  nvimTemplate = noctaliaSettings.theme.templates.user.nvim_base16;

  # The rendered configuration exists only in the session, so validation uses the same
  # generation with a placeholder token instead of the secret.
  validationToml = (pkgs.formats.toml { }).generate "noctalia-validation.toml" (
    lib.recursiveUpdate noctaliaSettings {
      plugin_settings."pozzoo/hassio".ha_token = "validation-placeholder";
    }
  );
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
  && noctaliaSettings.shell.polkit_agent
  && noctaliaSettings.theme.source == "wallpaper"
  && noctaliaSettings.theme.pure_black_dark
  && noctaliaSettings.theme.templates.enable_builtin_templates
  && noctaliaSettings.theme.templates.enable_community_templates
  &&
    builtins.sort builtins.lessThan noctaliaSettings.theme.templates.builtin_ids == expectedBuiltinIds
  &&
    builtins.sort builtins.lessThan noctaliaSettings.theme.templates.community_ids
    == expectedCommunityIds
  && noctaliaSettings.shell.panel.control_center_placement == "attached"
  && noctaliaSettings.shell.panel.open_near_click_control_center
  && !noctaliaSettings.location.auto_locate
  && noctaliaSettings.location.address == "Hufelandstraße 55, 17036 Neubrandenburg, Deutschland"
  && noctaliaSettings.backdrop.enabled
  # Plugin selection and its options, including the injected secret.
  && builtins.sort builtins.lessThan noctaliaSettings.plugins.enabled == expectedPlugins
  && noctaliaSettings.plugins.auto_update == "none"
  &&
    noctaliaSettings.plugin_settings."pozzoo/hassio".ha_url == "https://hass.${cfg.my.topology.domain}"
  && builtins.hasAttr "services/home/moonraker_hass_token" user.sops.secrets
  && user.sops.templates ? "noctalia-config.toml"
  && user.systemd.user.services ? "noctalia-config-reload"
  && configTemplate.mode == "0400"
  && lib.hasInfix "sops-nix/secrets/rendered/noctalia-config.toml" configTemplate.path
  # Integrations: each application consumes the palette through a declared seam.
  && user.programs.vscode.mutableExtensionsDir
  && user.programs.vscode.profiles.default.userSettings."workbench.colorTheme" == "NoctaliaTheme"
  && lib.any (p: lib.hasInfix "base16-nvim" (p.name or "")) user.programs.nixvim.extraPlugins
  && lib.hasInfix "matugen" user.programs.nixvim.extraConfigLuaPost
  && nvimTemplate.output_path == "$XDG_CONFIG_HOME/nvim/lua/matugen.lua"
  && !(nvimTemplate ? post_hook)
  && startup == [ { argv = [ shell ]; } ]
  && !(builtins.elem 7391 cfg.networking.firewall.allowedTCPPorts)
  && cfg.networking.networkmanager.enable
  && cfg.hardware.bluetooth.enable
  && cfg.services.upower.enable
  && cfg.services.power-profiles-daemon.enable
then
  pkgs.runCommandLocal "niri-noctalia-check"
    {
      nativeBuildInputs = [
        pkgs.gnugrep
      ];
    }
    ''
      fail=0
      if ! ${lib.getExe cfg.programs.niri.package} validate -c ${niriConfig}; then
        echo 'niri-noctalia: generated Niri config is invalid' >&2
        fail=1
      fi
      if ! ${shell} config validate ${validationToml} > validator.log 2>&1; then
        cat validator.log >&2
        echo 'niri-noctalia: generated Noctalia config is invalid' >&2
        fail=1
      fi
      # Plugin settings for a plugin that is not loaded in this sandbox are expected; any
      # other warning is not.
      if grep -E '(^|[[:space:]])WARN([[:space:]]|$)' validator.log \
        | grep -v 'no loaded plugin with this id' > unexpected.log; then
        cat unexpected.log >&2
        echo 'niri-noctalia: Noctalia ignored or migrated a declared setting' >&2
        fail=1
      fi
      if [ ! -f ${lib.escapeShellArg noctaliaSettings.shell.avatar_path} ]; then
        echo 'niri-noctalia: the configured avatar is not an installed file' >&2
        fail=1
      fi
      if [ "$(readlink ${lib.escapeShellArg (toString configLink)})" != ${lib.escapeShellArg configTemplate.path} ]; then
        echo 'niri-noctalia: the shell config link does not point at the rendered file' >&2
        fail=1
      fi
      if ! grep -F '<SOPS:' ${lib.escapeShellArg (toString configTemplate.file)} >/dev/null; then
        echo 'niri-noctalia: the config template does not carry a secret placeholder' >&2
        fail=1
      fi
      if ! grep -F 'color_scheme_path=' ${qt6ctConfig} >/dev/null \
        || ! grep -F 'qt6ct/colors/noctalia.conf' ${qt6ctConfig} >/dev/null; then
        echo 'niri-noctalia: qt6ct does not select the generated Noctalia palette' >&2
        fail=1
      fi
      if [ ! -f ${lib.escapeShellArg nvimTemplate.input_path} ]; then
        echo 'niri-noctalia: the vendored Neovim template is not an installed file' >&2
        fail=1
      fi
      if ! grep -F 'theme = noctalia' ${ghosttyConfig} >/dev/null; then
        echo 'niri-noctalia: generated Ghostty config does not select the Noctalia theme' >&2
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
        'Alt+Tab' \
        'QT_QPA_PLATFORMTHEME' \
        "include \"${user.xdg.configHome}/niri/noctalia.kdl\" optional=true"; do
        if ! grep -F -- "$expected" ${niriConfig} >/dev/null; then
          echo "niri-noctalia: generated Niri config is missing $expected" >&2
          fail=1
        fi
      done
      if grep -Ei 'axis-shell|\.config/axis|org\.axis' ${niriConfig} >&2; then
        echo 'niri-noctalia: generated Niri config contains Axis' >&2
        fail=1
      fi
      # The shell owns every seam to an application. A feature outside this shell's own
      # directory naming it means that ownership has leaked.
      if grep -ril 'noctalia' ${lib.escapeShellArg (toString self)}/features --exclude-dir=noctalia > leaked.log; then
        cat leaked.log >&2
        echo 'niri-noctalia: a feature outside features/desktop/noctalia mentions the shell' >&2
        fail=1
      fi
      [ "$fail" -eq 0 ] || exit 1
      echo 'Niri session and generated Niri/Noctalia configurations validated' > "$out"
    ''
else
  throw "niri-noctalia: workstation session, single shell startup, required services or closed Axis port failed"
