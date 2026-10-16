{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  bash,
  bun,
  cacert,
  electron_43,
  nodejs_24,
  python3,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  glib,
  gtk3,
  gtk4,
  gsettings-desktop-schemas,
  runCommand,
  xvfb-run,
  git,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  electron = electron_43;
  src = fetchFromGitHub {
    inherit (manifest.upstream) owner repo;
    tag = "v${manifest.version}";
    hash = manifest.srcHash;
  };
  bunDeps = stdenvNoCC.mkDerivation {
    pname = "openchamber-node-modules";
    inherit (manifest) version;
    inherit src;
    nativeBuildInputs = [
      bun
      cacert
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR/home
      export BUN_INSTALL_CACHE_DIR=$TMPDIR/bun-cache
      bun install --frozen-lockfile --ignore-scripts --no-progress --linker hoisted
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      find . -type d -name node_modules -prune -exec cp -R --parents {} $out \;
      runHook postInstall
    '';
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = manifest.bunDepsHash;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "openchamber-desktop";
  inherit (manifest) version;
  inherit src;

  nativeBuildInputs = [
    bun
    nodejs_24
    python3
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    glib
    gtk3
    gtk4
    gsettings-desktop-schemas
  ];
  dontWrapGApps = true;
  # Electron already carries Nixpkgs' runtime paths; patch only npm addons.
  dontAutoPatchelf = true;

  patches = [ ./managed-hosts.patch ];

  postPatch = ''
    cp ${./managed-hosts.mjs} packages/electron/managed-hosts.mjs
    cp ${./managed-runtime.mjs} packages/ui/src/lib/managed-runtime.mjs
    # Nix owns updates. Keep the UI's update query usable without contacting
    # electron-updater or offering to replace an immutable store installation.
    substituteInPlace packages/electron/main.mjs \
      --replace-fail 'const setupAutoUpdater = () => {' 'const setupAutoUpdater = () => { return;' \
      --replace-fail "case 'desktop_check_for_updates': {" \
        "case 'desktop_check_for_updates': { return { available: false, currentVersion: APP_VERSION, version: null, body: null, date: null } ;"
    substituteInPlace packages/electron/updater-capability.mjs \
      --replace-fail "if (platform !== 'linux' || !packaged) return;" \
        "throw new Error('OpenChamber updates are managed by Nix. Rebuild your NixOS configuration.');"
  '';

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR/home
    cp -R ${bunDeps}/. .
    chmod -R u+w node_modules packages/*/node_modules
    patchShebangs node_modules packages/*/node_modules
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    bun run --cwd packages/sdk build
    bun run --cwd packages/web build
    bun packages/electron/scripts/bundle-main.mjs
    # Compile against the exact Electron headers used at runtime, offline.
    (cd node_modules/node-pty && node ${nodejs_24}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js \
      rebuild --nodedir=${electron.headers})
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    runtime=$out/lib/openchamber
    app=$runtime/resources/app
    mkdir -p "$runtime" "$app/dist-bundle" $out/bin
    # A real executable gives Electron this package's resourcesPath. The
    # remaining runtime files can share Nixpkgs' patched Electron closure.
    cp -rs ${electron.dist}/. "$runtime/"
    rm "$runtime/electron"
    cp ${electron.dist}/electron "$runtime/openchamber"
    rm -rf "$runtime/resources"
    mkdir -p "$app/dist-bundle"
    cp packages/electron/dist-bundle/*.mjs "$app/dist-bundle/"
    cp packages/electron/{package.json,preload.mjs} "$app/"
    cp -R packages/web/dist "$runtime/resources/web-dist"
    cp -R packages/electron/resources/icons "$runtime/resources/icons"
    python3 ${./install-runtime.py} "$app"
    install -Dm444 packages/electron/resources/icons/app-icon.png \
      $out/share/icons/hicolor/512x512/apps/openchamber.png
    install -Dm444 LICENSE $out/share/licenses/openchamber-desktop/LICENSE
    runHook postInstall
  '';

  preFixup = ''
    makeWrapper "$out/lib/openchamber/openchamber" "$out/bin/openchamber-desktop" \
      "''${gappsWrapperArgs[@]}" \
      --set CHROME_DEVEL_SANDBOX "$out/lib/openchamber/chrome-sandbox"
  '';

  postFixup = ''
    autoPatchelf "$out/lib/openchamber/resources/app"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$TMPDIR/check-home
    mkdir -p "$HOME"
    ELECTRON_RUN_AS_NODE=1 "$out/lib/openchamber/openchamber" \
      ${./smoke.cjs} "$out/lib/openchamber" ${bash}/bin/bash
    runHook postInstallCheck
  '';

  passthru = {
    inherit bunDeps electron;
    tests.gui =
      runCommand "openchamber-desktop-gui-check"
        {
          nativeBuildInputs = [
            nodejs_24
            xvfb-run
            git
          ];
        }
        ''
          node ${./smoke-gui.mjs} ${finalAttrs.finalPackage}/bin/openchamber-desktop
          touch $out
        '';
  };

  meta = {
    description = "OpenChamber desktop workspace";
    homepage = "https://openchamber.dev";
    license = lib.licenses.mit;
    mainProgram = "openchamber-desktop";
    platforms = [ "x86_64-linux" ];
  };
})
