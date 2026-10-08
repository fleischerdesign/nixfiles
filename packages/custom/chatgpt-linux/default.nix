{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zstd,
  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libsecret,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  openssl,
  pango,
  qt5,
  qt6,
  systemd,
  tpm2-tss,
  wayland,
  xdg-utils,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
stdenv.mkDerivation {
  pname = manifest.name;
  inherit (manifest) version;
  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/arch/${manifest.version}/${manifest.upstream.architecture}/chatgpt-bin-${manifest.version}-1-${manifest.upstream.architecture}.pkg.tar.zst";
    inherit (manifest) hash;
  };

  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    zstd
  ];
  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libGL
    libnotify
    libsecret
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    openssl
    pango
    (lib.getLib qt5.qtbase)
    (lib.getLib qt6.qtbase)
    stdenv.cc.cc.lib
    systemd
    tpm2-tss
    wayland
  ];
  # Upstream also ships optional musl prebuilts, which need the musl libc.
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];
  runtimeDependencies = [
    libGL
    libsecret
    systemd
    wayland
  ];
  dontBuild = true;
  dontStrip = true;

  # autoPatchelf moves PT_INTERP past detect-libc's 2 KiB scan window, so its
  # familySync() fallback reports the musl family and its process.report call
  # trips Electron's CFI: the Git worker dies with SIGILL as soon as it watches
  # a repository. Pin the bundled detect-libc to glibc, keeping the byte length
  # identical so the app.asar header offsets stay valid.
  # https://github.com/NixOS/nixpkgs/commit/8917735c8596eb80ea5be8b2f4a02fd6b246041c
  postPatch = ''
    sed -i "s|const family = familySync();|const family = 'glibc'     ;|" usr/lib/chatgpt/resources/app.asar
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin" "$out/share"
    cp -a usr/lib/chatgpt "$out/lib/"
    cp -a usr/share/applications usr/share/pixmaps usr/share/metainfo "$out/share/"
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail 'Exec=chatgpt' "Exec=$out/bin/chatgpt"
    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --add-flags '--ozone-platform=wayland' \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}"
    runHook postInstall
  '';

  meta = {
    description = "Official ChatGPT Linux desktop application with native Wayland";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
  };
}
