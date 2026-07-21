# packages/custom/hermes-desktop/default.nix
# Native Rust compilation for Hermes WebUI Desktop (Tauri 2)
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook3,
  webkitgtk_4_1,
  gtk3,
  libsoup_3,
  openssl,
  dbus,
  librsvg,
  glib,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  pname = manifest.name;
  inherit (manifest) version srcHash cargoHash;
in
rustPlatform.buildRustPackage {
  inherit pname version cargoHash;

  src = fetchFromGitHub {
    owner = manifest.upstream.owner;
    repo = manifest.upstream.repo;
    rev = "v${version}";
    hash = srcHash;
  };

  sourceRoot = "source/src-tauri";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook3
  ];
  buildInputs = [
    webkitgtk_4_1
    gtk3
    libsoup_3
    openssl
    dbus
    librsvg
    glib
  ];

  postInstall = ''
    ln -s $out/bin/hermes-webui-desktop $out/bin/hermes-desktop
    install -m 444 -D ../src-tauri/icons/icon.png $out/share/icons/hicolor/512x512/apps/hermes-desktop.png || true
  '';

  meta = with lib; {
    description = "Official native Tauri 2 desktop application for Hermes WebUI";
    homepage = "https://github.com/hermes-webui/hermes-desktop-rust";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hermes-webui-desktop";
  };
}
