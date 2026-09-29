# features/desktop/noctalia/config.nix - render the shell's configuration in the session.
#
# The Home Assistant token cannot be written into a Nix store file. When that plugin is
# selected the configuration is generated here, rendered by sops-nix with the user's own
# age identity, and linked into place; without a secret the generated file is linked
# directly. `my.features.desktop.noctalia.settings` stays the single declaration, and this
# module is the only thing that knows how it reaches disk.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;

  # The token is shared with Klipper's Moonraker by explicit decision; both consumers name
  # the same secret so a reader can see that one credential has two of them.
  haToken = "services/home/moonraker_hass_token";
  haPlugin = "pozzoo/hassio";
  haEnabled = lib.elem haPlugin (cfg.settings.plugins.enabled or [ ]);

  tomlFormat = pkgs.formats.toml { };

  plainToml = tomlFormat.generate "noctalia-config.toml" cfg.settings;

  secretToml =
    if haEnabled then
      tomlFormat.generate "noctalia-config.toml" (
        lib.recursiveUpdate cfg.settings {
          plugin_settings.${haPlugin}.ha_token = config.sops.placeholder.${haToken};
        }
      )
    else
      null;

  # The generated input changes with the declared settings, so it is what a switch has to
  # notice; the linked file itself is stable and only exists at runtime.
  configSource = if haEnabled then secretToml else plainToml;
in
{
  config = lib.mkIf cfg.enable {
    # Declaring the secret is what produces the placeholder above and starts sops-nix in the
    # session; it also renders the secret on its own under the user's runtime directory.
    sops.secrets.${haToken} = lib.mkIf haEnabled { };

    sops.templates."noctalia-config.toml" = lib.mkIf haEnabled {
      file = secretToml;
      mode = "0400";
    };

    # The shell reads this at session start; the symlink is created by Home Manager at
    # activation and may dangle until sops-nix has rendered its target.
    xdg.configFile."noctalia/config.toml".source =
      if haEnabled then
        config.lib.file.mkOutOfStoreSymlink config.sops.templates."noctalia-config.toml".path
      else
        plainToml;

    # The running shell does not notice that its configuration file was replaced - it is a
    # symlink whose target moved - so a switch has to tell it. The unit restarts when the
    # configuration content changes, waits for the shell, and fails loudly if it never
    # answers.
    systemd.user.services.noctalia-config-reload = {
      Unit = {
        Description = "Reload Noctalia's configuration after it changed";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        X-Restart-Triggers = [ configSource ];
        StartLimitBurst = 30;
        StartLimitIntervalSec = 120;
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe config.programs.noctalia.package} msg config-reload";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
