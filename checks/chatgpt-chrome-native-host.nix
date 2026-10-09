# checks/chatgpt-chrome-native-host.nix
#
# Two measurements. The artifact one runs the vendor's own manifest checker against the file the
# derivation generates - the same verdict Chrome's native messaging lookup is built on - plus the
# facts that checker does not look at: the transport type and an executable program behind the
# manifest. The projection one states that every host carrying the ChatGPT feature also carries
# those manifests in its user's config.
{
  pkgs,
  lib,
  self,
  ...
}:
let
  nativeHost = import ../features/desktop/chatgpt/native-host.nix {
    inherit pkgs lib;
    # A placeholder: the real Codex home belongs to the user, and this check cannot see it. The
    # existence assertions below therefore skip it.
    codexHome = "/codex-home";
  };
  app = pkgs.custom.chatgpt-linux;
  plugin = "${app}/lib/chatgpt/resources/plugins/openai-bundled/plugins/chrome";

  expectedConfigFiles = map (
    directory: "${directory}/${nativeHost.hostName}.json"
  ) nativeHost.configDirectories;
  runtimeManifest = nativeHost.runtimeManifestFile;
  graphicalHosts = lib.filterAttrs (
    _: host: host.config.my.role != "server"
  ) self.nixosConfigurations;

  projectionProblems = lib.concatLists (
    map (
      name:
      let
        host = self.nixosConfigurations.${name};
        user = host.config.home-manager.users.${host.config.my.user.primary};
        enabled = lib.attrByPath [ "my" "features" "desktop" "chatgpt" "enable" ] false user;
        missing = lib.filter (file: !(user.xdg.configFile ? ${file})) expectedConfigFiles;
      in
      lib.optional (enabled && missing != [ ]) "${name}: ${lib.concatStringsSep ", " missing}"
    ) (lib.attrNames graphicalHosts)
  );
in
if projectionProblems != [ ] then
  throw "ChatGPT Chrome native host manifest is not projected for: ${lib.concatStringsSep "; " projectionProblems}"
else
  pkgs.runCommandLocal "chatgpt-chrome-native-host-check"
    {
      nativeBuildInputs = [
        pkgs.jq
        pkgs.python3
      ];
    }
    ''
        set -euo pipefail

        # Expectation: the vendor checker accepts this file for Chrome - manifest present, host name
        # matches, both extension origins allowed. It exits non-zero and prints its verdict otherwise,
        # which is exactly what we want to see here.
        CODEX_CHROMIUM_NATIVE_HOST_MANIFEST_PATH=${nativeHost.manifestFile} ${app}/lib/chatgpt/resources/cua_node/bin/node ${plugin}/scripts/check-native-host-manifest.js --browser chrome --json

        # Expectations the vendor checker does not cover: Chrome launches the program named in path
        # over stdio, and every path the host config names has to exist in this package.
        test "$(jq -r .type ${nativeHost.manifestFile})" = "stdio"
        test -x "$(jq -r .path ${nativeHost.manifestFile})"

        hostConfig=${nativeHost.package}/extension-host/linux/x64/extension-host-config.json
        test "$(jq -r .schemaVersion "$hostConfig")" = "1"
        for key in browserClientPath codexCliPath nodePath nodeReplPath; do
          value=$(jq -r ".$key" "$hostConfig")
          if [ ! -e "$value" ]; then
            echo "host config $key points at a missing path: $value" >&2
            exit 1
          fi
        done

        # The registration the extension needs: schema version 2, one entry, and every path it names
        # present in this closure.
        test "$(jq -r .schemaVersion ${runtimeManifest})" = "2"
        test "$(jq -r '.entries | length' ${runtimeManifest})" = "1"
        test "$(jq -r '.entries[0].appServerProtocolVersion' ${runtimeManifest})" = "2"
        test "$(jq -r '.entries[0].nativeHostNames[0]' ${runtimeManifest})" = ${lib.escapeShellArg nativeHost.hostName}
      for key in browserClientPath browserServicePath codexCliPath extensionHostPath nodePath nodeReplPath resourcesPath; do
        value=$(jq -r ".entries[0].paths.$key" ${runtimeManifest})
        if [ ! -e "$value" ]; then
          echo "runtime manifest path $key is missing: $value" >&2
            exit 1
          fi
        done

        # And the consumer-level measurement: the host has to answer the extension's own handshake and
        # serve it a runtime for this registration.
        python3 ${./chatgpt-chrome-runtime-probe.py} ${nativeHost.package}/extension-host/linux/x64/extension-host ${runtimeManifest} hehggadaopoacecdllhhajmbjkdcmajg

        touch $out
    ''
