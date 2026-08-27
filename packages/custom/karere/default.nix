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
    url = "https://github.com/tobagin/karere/releases/download/cef-150.0.10-proprietary-codecs/cef_binary_150.0.10%2Bg8042e43%2Bchromium-150.0.7871.101_linux64_minimal.zip";
    hash = "sha256-O74pg2jE2HwZrZt+1OhEnqkbMv+jzvyGcnkaG5bJw7k=";
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
    cat <<EOF > "$CEF_PATH/archive.json"
    {
      "type": "minimal",
      "name": "cef_binary_150.0.10",
      "sha1": "3bbe298368c4d87c19ad9b7ed4e8449ea91b32ffa3cefc8672791a1b96c9c3b9"
    }
    EOF
    ln -sfn "$CEF_PATH/Resources/locales" "$CEF_PATH/locales"
    ln -sfn "$CEF_PATH"/Release/*.so* "$CEF_PATH/"
    ln -sfn "$CEF_PATH"/Resources/* "$CEF_PATH/"
  '';

  preConfigure = ''
    export CEF_PATH="$(echo $PWD/../cef-dir/*)"
    cat <<EOF > "$CEF_PATH/archive.json"
    {
      "type": "minimal",
      "name": "cef_binary_150.0.10",
      "sha1": "3bbe298368c4d87c19ad9b7ed4e8449ea91b32ffa3cefc8672791a1b96c9c3b9"
    }
    EOF
    ln -sfn "$CEF_PATH/Resources/locales" "$CEF_PATH/locales"
    ln -sfn "$CEF_PATH"/Release/*.so* "$CEF_PATH/"
    ln -sfn "$CEF_PATH"/Resources/* "$CEF_PATH/"
  '';

  preBuild = ''
    autoPatchelf "$CEF_PATH"
  '';

  postInstall = ''
    mkdir -p "$out/lib/karere"
    cp -rL "$CEF_PATH"/* "$out/lib/karere/"
    mkdir -p "$out/bin"
    ln -sfn "$out/lib/karere"/* "$out/bin/" 2>/dev/null || true
  '';

  preFixup = ''
    patchelf --set-rpath "$out/lib/karere:${lib.makeLibraryPath finalAttrs.buildInputs}" "$out/bin/karere"
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
