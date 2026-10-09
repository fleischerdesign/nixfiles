{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  nativeHost = import ./native-host.nix {
    inherit pkgs lib;
    codexHome = config.home.sessionVariables.CODEX_HOME or "${config.home.homeDirectory}/.codex";
  };
  # The app itself resolves the state directory the same way: XDG_STATE_HOME, else ~/.local/state.
  stateHome =
    if config.xdg.stateHome != null then
      config.xdg.stateHome
    else
      "${config.home.homeDirectory}/.local/state";
in
{
  options.my.features.desktop.chatgpt.enable = lib.mkEnableOption "ChatGPT desktop for this user";
  config =
    lib.mkIf (osConfig.my.features.desktop.chatgpt.enable && config.my.features.desktop.chatgpt.enable)
      {
        home.packages = [ pkgs.custom.chatgpt-linux ];
        xdg.mimeApps.defaultApplications."x-scheme-handler/codex" = "chatgpt.desktop";

        # Chrome finds the desktop app through a native messaging manifest. The app's installer
        # cannot write it under this packaging, so native-host.nix generates it with that same
        # installer and this projects it into every config directory Chrome reads.
        xdg.configFile = lib.listToAttrs (
          map (
            directory:
            lib.nameValuePair "${directory}/${nativeHost.hostName}.json" {
              source = nativeHost.manifestFile;
            }
          ) nativeHost.configDirectories
        );

        # The extension reaches the app-server through the registration the app writes to
        # chrome-native-hosts-v2.json. The app's own installation step never completes under this
        # packaging, so this writes the file the app would write. Real files, not store links, so a
        # working app installation can take the registration over later.
        home.activation.chatgptChromeRuntimeManifest = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run install -Dm600 ${nativeHost.runtimeManifestFile} "$HOME/.codex/chrome-native-hosts-v2.json"
          run install -Dm600 ${nativeHost.runtimeManifestFile} "${stateHome}/openai-codex/chrome-native-hosts-v2.json"
        '';

        # The browser service the node REPL loads lives in the plugin cache; the app would put it
        # there while installing its bundled plugins, which never happens under this packaging.
        home.activation.chatgptChromePluginCache = lib.hm.dag.entryAfter [
          "writeBoundary"
        ] nativeHost.pluginCacheScript;
      };
}
