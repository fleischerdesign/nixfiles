# features/desktop/chatgpt/native-host.nix
#
# Chrome reaches the ChatGPT desktop app through its native messaging channel: the extension asks
# for the host com.openai.codexextension, Chrome reads a manifest from its own config directory
# and launches the program that manifest names. The app ships that program and an installer which
# writes the manifest plus a config file next to the binary - but the installer writes where it
# runs from, and it runs from the read-only store, so it never completes under this packaging and
# Chrome keeps offering to install the app.
#
# Instead of re-implementing the installer's output, this runs the vendor installer in a writable
# build directory and publishes its two artifacts. The installer is version-matched to the
# installed app, so a release that changes the shape of either file breaks the build here rather
# than shipping a stale guess. Host name, extension origins and destination directories are read
# from the app's own extension-ids.json, so no fact is written twice.
{
  pkgs,
  lib,
  codexHome,
}:
let
  app = pkgs.custom.chatgpt-linux;
  resources = "${app}/lib/chatgpt/resources";
  plugin = "${app}/lib/chatgpt/resources/plugins/openai-bundled/plugins/chrome";
  node = "${app}/lib/chatgpt/resources/cua_node/bin/node";

  xdgConfigPrefix = ".config/";

  metadata = builtins.fromJSON (builtins.readFile "${plugin}/scripts/extension-ids.json");
  hostName = metadata.extensionHostName;
  extensionIds = metadata.extensionIds;
  # Chrome compares the origin exactly, including the trailing slash.
  allowedOrigins = map (id: "chrome-extension://${id}/") extensionIds;
  # The installer writes one manifest per Chromium-family config directory; the destinations come
  # from its own list rather than a second one maintained here.
  manifestDirectories = lib.unique (
    lib.concatMap (
      browser: browser.linux.nativeMessagingManifestDirectories or [ ]
    ) metadata.browserDiagnostics
  );

  # Chrome only reads native messaging manifests under XDG_CONFIG_HOME, so an entry somewhere
  # else would be written where Chrome never looks. Refuse to guess at evaluation time.
  configDirectories =
    if
      manifestDirectories == [ ]
      || !(lib.all (directory: lib.hasPrefix xdgConfigPrefix directory) manifestDirectories)
    then
      throw ''
        ChatGPT extension-ids.json no longer lists Linux native messaging directories under ${xdgConfigPrefix}:
        ${lib.concatStringsSep ", " manifestDirectories}
      ''
    else
      map (lib.removePrefix xdgConfigPrefix) manifestDirectories;

  package =
    pkgs.runCommand "chatgpt-chrome-native-host-${app.version}" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        set -euo pipefail

        mkdir -p "$out/scripts" "$TMPDIR/home"
        cp -a ${plugin}/extension-host "$out/extension-host"
        cp ${plugin}/scripts/installManifest.mjs "$out/scripts/installManifest.mjs"
        # The installer writes the host config next to the host binary, so that directory has to be
        # writable while it runs.
        chmod -R u+w "$out/extension-host"

        # The installer takes the plugin root from its own location, so it has to run from $out, and
        # the runtime paths from its arguments - the same values the app passes at runtime.
        # browserClientPath points into the app bundle because the plugin's scripts stay there.
        cat > "$TMPDIR/install-native-host.mjs" <<EOF
        import { install } from "$out/scripts/installManifest.mjs";

        await install({
          appServerRuntimePaths: {
            browserClientPath: "${plugin}/scripts/browser-client.mjs",
            codexCliPath: "${app}/lib/chatgpt/resources/codex",
            nodePath: "${node}",
            nodeReplPath: "${app}/lib/chatgpt/resources/cua_node/bin/node_repl",
          },
        });
        EOF

        # Chrome inherits its environment from the session, but the build must not depend on it.
        env -u XDG_CONFIG_HOME -u CHROME_CONFIG_HOME HOME=$TMPDIR/home ${node} "$TMPDIR/install-native-host.mjs"

        manifestSource="$TMPDIR/home/${xdgConfigPrefix}google-chrome/NativeMessagingHosts/${hostName}.json"
        install -Dm444 "$manifestSource" "$out/share/native-messaging-hosts/${hostName}.json"
        # The installer only needed its own copy to locate the plugin root.
        rm -rf "$out/scripts"

        manifest="$out/share/native-messaging-hosts/${hostName}.json"
        hostConfig="$out/extension-host/linux/x64/extension-host-config.json"
        extensionHost="$out/extension-host/linux/x64/extension-host"

        test -x "$extensionHost"
        test "$(jq -r .name "$manifest")" = ${lib.escapeShellArg hostName}
        test "$(jq -r .type "$manifest")" = "stdio"
        test "$(jq -r .path "$manifest")" = "$extensionHost"
        test "$(jq -r '.allowed_origins | join(",")' "$manifest")" = ${lib.escapeShellArg (lib.concatStringsSep "," allowedOrigins)}
        test "$(jq -r .schemaVersion "$hostConfig")" = "1"
        for key in browserClientPath codexCliPath nodePath nodeReplPath; do
          value=$(jq -r ".$key" "$hostConfig")
          if [ ! -e "$value" ]; then
            echo "host config $key points at a missing path: $value" >&2
            exit 1
          fi
        done
      '';

  # The desktop app registers its app-server for the extension in chrome-native-hosts-v2.json.
  # Without that file the native host answers codexRuntime/hello with "Codex Chrome native host v2
  # manifest is missing" and the extension can never start a runtime. The app writes it while
  # installing its bundled Chrome plugin, a step that does not complete under this packaging, so
  # it is generated here from the same inputs.
  runtimeManifest =
    pkgs.runCommand "chatgpt-chrome-runtime-manifest-${app.version}"
      { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${./write-runtime-manifest.py} "$out" ${lib.escapeShellArg hostName} ${lib.escapeShellArg app.version} ${lib.escapeShellArg "${package}/extension-host/linux/x64/extension-host"} ${lib.escapeShellArg resources} ${lib.escapeShellArg codexHome} ${lib.escapeShellArg plugin} ${lib.escapeShellArgs extensionIds}
      '';

  # The node REPL loads the browser service from the plugin cache, and the agent imports the
  # browser client from the plugin root it is handed - both live under the user's plugin cache,
  # which the app fills while installing its bundled plugins. That step never completes under this
  # packaging, so the plugins are copied there by the activation in home.nix. Copies, not store
  # links: the node REPL trusts paths inside the user's own directories, and a link would resolve
  # out of them.
  cachedPlugins = [
    {
      name = "browser";
      source = "${resources}/plugins/openai-bundled/plugins/browser";
    }
    {
      name = "chrome";
      source = plugin;
    }
  ];

  pluginCacheRoot = "${codexHome}/plugins/cache/openai-bundled";
  pluginCacheScript = lib.concatMapStrings (cached: ''
    target=${pluginCacheRoot}/${cached.name}/${app.version}
    run mkdir -p ${pluginCacheRoot}/${cached.name}
    if [ ! -d "$target" ]; then
      run cp -a ${cached.source} "$target"
      run chmod -R u+w "$target"
    fi
    run ln -sfn ${app.version} ${pluginCacheRoot}/${cached.name}/latest
  '') cachedPlugins;
in
{
  inherit
    hostName
    allowedOrigins
    configDirectories
    package
    ;

  manifestFile = "${package}/share/native-messaging-hosts/${hostName}.json";
  runtimeManifestFile = "${runtimeManifest}/share/codex-runtime-manifest/chrome-native-hosts-v2.json";
  inherit pluginCacheScript;
}
