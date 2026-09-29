# Noctalia Greeter. It is the login screen of the same shell, so it lives in the shell's
# feature and only where the shell is enabled.
#
# The greeter is not a session: it asks for credentials and starts the session that the
# desktop contract already knows. Its most important effect is the one it removes: a login
# with a password gives `pam_gnome_keyring` the authtok it needs, so the login keyring is
# unlocked when the session starts instead of when the lock screen is dismissed.
#
# Appearance is synced from the shell rather than duplicated: the greeter reads the mutable
# `sync.toml` beside the declarative `greeter.toml`, and `passwordlessSyncUsers` authorises
# the constrained apply helper for the primary user, so the login screen looks like the
# desktop without a second copy of the palette living here.
#
# This is the system half: the greeter runs before any session exists.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf cfg.enable {
    services.displayManager.noctalia-greeter = {
      enable = true;

      # The cursor matches the session's, from the same package the compositor uses. A theme
      # installed only in a home directory would be unreadable to the greeter account.
      cursorTheme = {
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
      };

      settings = {
        # The picker's spelling for Niri; lookup is case-insensitive.
        session.default = "niri";
        # The same layout the session gets, so the password is typed on the keyboard you
        # expect - the greeter cannot read the compositor's setting.
        keyboard.layout = "de";
        # `Synced` is what lets the shell's palette reach this screen; a built-in scheme here
        # would win over the synced values and the sync would have nothing to show.
        appearance.scheme = "Synced";
      };

      # The constrained appearance-sync action is authorised for the primary user, because
      # the only thing that changes the login screen's look is the shell that user runs.
      passwordlessSyncUsers = [ config.my.user.primary ];
    };
  };
}
