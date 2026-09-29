# Verify the workstation's shell session and the configuration it actually delivers.
#
# This checks properties, not a copy of the configuration: a claim is either a relation
# between two declarations (an integration that selects a template must also wire the
# application) or a requirement the design cannot work without. A personal choice - which
# widget sits in which lane, which address is configured - is deliberately not asserted;
# changing it is not a defect. Every violated claim is named in the error.
{
  pkgs,
  lib,
  self,
  ...
}:
let
  cfg = self.nixosConfigurations.hom-wrk-01.config;
  user = cfg.home-manager.users.${cfg.my.user.primary};
  settings = user.my.features.desktop.noctalia.settings;

  shell = lib.getExe user.programs.noctalia.package;
  niriConfig = user.xdg.configFile.niri-config.source;
  ghosttyConfig = user.xdg.configFile."ghostty/config".source;
  qt6ctConfig = user.xdg.configFile."qt6ct/qt6ct.conf".source;
  configLink = user.xdg.configFile."noctalia/config.toml".source;
  configTemplate = user.sops.templates."noctalia-config.toml";

  token = "services/home/moonraker_hass_token";
  environment = cfg.my.desktop.environments;
  templates = settings.theme.templates;

  laneEntries = lib.concatLists (
    map (lane: settings.bar.default.${lane} or [ ]) [
      "start"
      "center"
      "end"
    ]
  );
  # A lane entry naming a plugin is "<author>/<plugin>:<entry>"; "group:" tokens are not
  # plugins. Both the lane and the named widget definitions are checked against the plugins
  # that are enabled, so a widget can never point at a plugin that is not selected.
  pluginReference = entry: lib.hasInfix ":" entry && !(lib.hasPrefix "group:" entry);
  pluginOf = entry: builtins.head (lib.splitString ":" entry);
  referencedPlugins =
    map pluginOf (builtins.filter pluginReference laneEntries)
    ++ map pluginOf (
      builtins.filter pluginReference (
        lib.mapAttrsToList (_: widget: widget.type or "") (settings.widget or { })
      )
    );
  enabledPlugins = settings.plugins.enabled or [ ];
  settingsPlugins = lib.attrNames (settings.plugin_settings or { });
  namedWidgets = lib.attrNames (settings.widget or { });

  # The phone plugin is a plugin that runs external tools; on NixOS each has to be in the
  # session profile, so the check verifies the profile rather than the declaration.
  phonePlugin = "icefish/phone-operate";
  phonePluginEnabled = lib.elem phonePlugin enabledPlugins;
  phoneTools = [
    "scrcpy"
    "adb"
    "sshfs"
    "gdbus"
  ];

  # Each claim is a property. The error names the ones that do not hold.
  claims = {
    # The session belongs to Niri alone, and greetd starts it directly as the primary user.
    "one-graphical-environment" =
      environment.niri
      && builtins.length (lib.attrNames (lib.filterAttrs (_: running: running) environment)) == 1;
    "greetd-starts-the-shell-directly" =
      cfg.services.greetd.enable
      && cfg.services.greetd.settings.default_session.user == cfg.my.user.primary
      &&
        cfg.services.greetd.settings.default_session.command
        == "${cfg.programs.niri.package}/bin/niri-session"
      && !cfg.services.displayManager.gdm.enable
      && !cfg.services.desktopManager.gnome.enable;

    # The shell is the session's, runs once, and owns the Polkit prompt.
    "shell-runs-once-in-the-session" =
      user.programs.noctalia.enable
      && !user.programs.noctalia.systemd.enable
      && user.programs.niri.settings.spawn-at-startup == [ { argv = [ shell ]; } ];
    "shell-owns-the-polkit-prompt" = settings.shell.polkit_agent;

    # Every selected template id is selected once, so no integration double-adds one.
    "templates-are-not-selected-twice" =
      templates.enable_builtin_templates
      && templates.enable_community_templates
      && templates.builtin_ids == lib.unique templates.builtin_ids
      && templates.community_ids == lib.unique templates.community_ids;

    # Every plugin reference resolves to an enabled plugin, and no plugin settings are
    # declared for a plugin that is not enabled.
    "plugin-widgets-belong-to-enabled-plugins" = builtins.all (
      id: builtins.elem id enabledPlugins
    ) referencedPlugins;
    "plugin-settings-belong-to-enabled-plugins" = builtins.all (
      id: builtins.elem id enabledPlugins
    ) settingsPlugins;
    # A plugin whose user interface needs a system service must find that service enabled.
    "phone-plugin-has-its-system-service" =
      !(lib.elem "icefish/phone-operate" enabledPlugins) || cfg.programs.kdeconnect.enable;
    "named-widgets-are-referenced" = builtins.all (name: builtins.elem name laneEntries) namedWidgets;

    # A configured avatar must be an installed file; an unset one is fine.
    "avatar-resolves" =
      !(settings.shell ? avatar_path) || builtins.pathExists settings.shell.avatar_path;

    # The Home Assistant token is rendered in the session, not built into the store.
    "secret-is-declared" = builtins.hasAttr token user.sops.secrets;
    "config-is-rendered-at-runtime" =
      user.sops.templates ? "noctalia-config.toml"
      && configTemplate.mode == "0400"
      && lib.hasInfix "sops-nix/secrets/rendered/noctalia-config.toml" configTemplate.path;
    "config-reload-unit-exists" = user.systemd.user.services ? "noctalia-config-reload";

    # An integration that selects a template must also wire the application, or the
    # template would produce a palette nothing reads.
    "ghostty-consumes-the-palette" =
      !(lib.elem "ghostty" templates.builtin_ids)
      || user.programs.ghostty.settings.theme == [ "noctalia" ];
    "qt-consumes-the-palette" =
      !(lib.elem "qt" templates.builtin_ids)
      || lib.hasInfix "noctalia.conf" user.xdg.configFile."qt6ct/qt6ct.conf".text;
    "vscode-consumes-the-palette" =
      !(lib.elem "vscode" templates.community_ids)
      || (
        user.programs.vscode.mutableExtensionsDir
        && user.programs.vscode.profiles.default.userSettings."workbench.colorTheme" == "NoctaliaTheme"
      );
    "neovim-consumes-the-palette" =
      !(cfg.my.features.dev.nixvim.enable or false)
      || (
        lib.any (p: lib.hasInfix "base16-nvim" (p.name or "")) user.programs.nixvim.extraPlugins
        && lib.hasInfix "matugen" user.programs.nixvim.extraConfigLuaPost
        && !(templates.user.nvim_base16 ? post_hook)
      );

    # The shell needs the workspace services it reports on.
    "workspace-services-are-present" =
      cfg.networking.networkmanager.enable
      && cfg.hardware.bluetooth.enable
      && cfg.services.upower.enable
      && cfg.services.power-profiles-daemon.enable;
  };

  violated = lib.attrNames (lib.filterAttrs (_: holds: !holds) claims);

  # The rendered configuration exists only in the session, so validation uses the same
  # generation with a placeholder token instead of the secret.
  validationToml = (pkgs.formats.toml { }).generate "noctalia-validation.toml" (
    lib.recursiveUpdate settings {
      plugin_settings."pozzoo/hassio".ha_token = "validation-placeholder";
    }
  );
in
if violated != [ ] then
  throw "niri-noctalia: these claims do not hold: ${lib.concatStringsSep ", " violated}"
else
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
      if ! ${shell} config validate ${validationToml} > validator.log 2>&1; then
        cat validator.log >&2
        echo 'niri-noctalia: generated Noctalia config is invalid' >&2
        fail=1
      fi
      # The sandbox has no plugins loaded, so each declared plugin setting warns once. That
      # warning is expected; any other warning means a declared setting was ignored.
      grep -E '(^|[[:space:]])WARN([[:space:]]|$)' validator.log > warnings.log || true
      while IFS= read -r line; do
        case "$line" in
          *"plugin_settings."*"no loaded plugin with this id") ;;
          *)
            echo "$line" >&2
            echo 'niri-noctalia: Noctalia reported an unexpected warning' >&2
            fail=1
            ;;
        esac
      done < warnings.log
      for key in ${lib.concatMapStringsSep " " lib.escapeShellArg settingsPlugins}; do
        if ! grep -F "plugin_settings.$key: no loaded plugin with this id" warnings.log >/dev/null; then
          echo "niri-noctalia: the declared plugin settings for $key were not validated" >&2
          fail=1
        fi
      done
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
      if [ ! -f ${lib.escapeShellArg templates.user.nvim_base16.input_path} ]; then
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
      # The shell owns every seam to an application. This is a lint for that one coupling:
      # an application feature must not name the shell.
      if grep -rl 'noctalia' ${lib.escapeShellArg (toString self)}/features/dev --include='*.nix' > leaked.log; then
        cat leaked.log >&2
        echo 'niri-noctalia: an application feature names the shell' >&2
        fail=1
      fi
      ${lib.optionalString phonePluginEnabled ''
        for tool in ${lib.concatStringsSep " " phoneTools}; do
          if [ ! -x ${lib.escapeShellArg "${user.home.path}/bin"}/"$tool" ]; then
            echo "niri-noctalia: the phone plugin needs $tool in the session profile" >&2
            fail=1
          fi
        done
      ''}
      [ "$fail" -eq 0 ] || exit 1
      echo 'Niri session and the delivered shell configuration validated' > "$out"
    ''
