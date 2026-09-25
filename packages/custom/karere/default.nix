# packages/custom/karere/default.nix
{
  alsa-lib,
  atk,
  autoPatchelfHook,
  blueprint-compiler,
  cairo,
  cargo,
  cmake,
  cups,
  dbus,
  desktop-file-utils,
  expat,
  fetchFromGitHub,
  fetchurl,
  fontconfig,
  freetype,
  glib,
  glib-networking,
  gst_all_1,
  lib,
  libadwaita,
  libdrm,
  libepoxy,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxtst,
  mesa,
  meson,
  ninja,
  nspr,
  nss,
  pango,
  patchelf,
  pkg-config,
  rustPlatform,
  rustc,
  stdenv,
  systemd,
  unzip,
  webkitgtk_6_0,
  wrapGAppsHook4,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
stdenv.mkDerivation (finalAttrs: {
  pname = manifest.name;
  inherit (manifest) version;
  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = manifest.upstream.owner;
    repo = manifest.upstream.repo;
    tag = "v${finalAttrs.version}";
    hash = manifest.srcHash;
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version src;
    hash = manifest.cargoHash;
  };

  cefBinary = fetchurl {
    name = "cef.zip";
    inherit (manifest.cef) url hash;
  };

  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    autoPatchelfHook
    blueprint-compiler
    cargo
    cmake
    desktop-file-utils
    meson
    ninja
    patchelf
    pkg-config
    rustPlatform.cargoSetupHook
    rustc
    unzip
    wrapGAppsHook4
  ];

  buildInputs = [
    alsa-lib
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    glib-networking
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    libadwaita
    libdrm
    libepoxy
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxtst
    mesa
    nspr
    nss
    pango
    systemd
    webkitgtk_6_0
  ];

  postUnpack = ''
    mkdir -p cef-dir
    unzip ${finalAttrs.cefBinary} -d cef-dir
    CEF_PATH="$(echo $PWD/cef-dir/*)"
    cp ${builtins.toFile "cef-archive.json" (builtins.toJSON manifest.cef.archive)} "$CEF_PATH/archive.json"
    ln -sfn "$CEF_PATH/Resources/locales" "$CEF_PATH/locales"
    ln -sfn "$CEF_PATH"/Release/*.so* "$CEF_PATH/"
    ln -sfn "$CEF_PATH"/Resources/* "$CEF_PATH/"
  '';

  preConfigure = ''
    export CEF_PATH="$(echo $PWD/../cef-dir/*)"
  '';

  preBuild = ''
    autoPatchelf "$CEF_PATH"
  '';

  postInstall = ''
    mkdir -p "$out/lib/karere"
    cp -a "$CEF_PATH"/Release/. "$out/lib/karere/"
    cp -a "$CEF_PATH"/Resources/. "$out/lib/karere/"
  '';

  preFixup = ''
    patchelf --set-rpath "$out/lib/karere:${lib.makeLibraryPath finalAttrs.buildInputs}" "$out/bin/karere"
    gappsWrapperArgs+=(
      --set CEF_PATH "$out/lib/karere"
      --prefix LD_LIBRARY_PATH : "$out/lib/karere"
    )
  '';

  meta = with lib; {
    description = "GTK4 + libadwaita + CEF native WhatsApp client";
    homepage = "https://github.com/tobagin/karere";
    license = licenses.gpl3Plus;
    mainProgram = "karere";
    maintainers = [ ];
    platforms = platforms.linux;
  };
})
