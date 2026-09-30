# Personal browser configuration, imported only by the graphical profile.
{
  programs.firefox = {
    enable = true;
    # Keep existing profiles at Firefox's traditional location.
    configPath = ".mozilla/firefox";
    policies.ExtensionSettings = {
      "uBlock0@raymondhill.net" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      };
      "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
      };
    };
  };
}
