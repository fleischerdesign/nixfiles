# packages/custom/hermes-desktop/default.nix
# Declarative AppImage wrapper for Hermes WebUI Desktop (Tauri 2)
{
  lib,
  appimageTools,
  fetchurl,
  ...
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  pname = manifest.name;
  inherit (manifest) version hash;

  src = fetchurl {
    url = "https://github.com/${manifest.upstream.owner}/${manifest.upstream.repo}/releases/download/v${version}/${manifest.upstream.assetName}";
    inherit hash;
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraBwrapArgs = [
    "--chdir"
    "/"
  ];

  extraPkgs =
    pkgs: with pkgs; [
      webkitgtk_4_1
      gtk3
      glib
      gdk-pixbuf
      cairo
      pango
      atk
      libsoup_3
      openssl
      dbus
      libxkbcommon
      wayland
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libglvnd
      libGL
      mesa
      vulkan-loader
      librsvg
    ];

  extraProfile = ''
    export PWD="$HOME"
    cd "$HOME"
    export HERMES_DESKTOP_SAFE_RENDER=1
    export WEBKIT_DISABLE_DMABUF_RENDERER=1
  '';

  extraInstallPhase = ''
    install -m 444 -D ${appimageContents}/Hermes.WebUI.Desktop.desktop $out/share/applications/hermes-desktop.desktop || true
    install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/512x512/apps/Hermes.WebUI.Desktop.png $out/share/icons/hicolor/512x512/apps/hermes-desktop.png || true

    substituteInPlace $out/share/applications/hermes-desktop.desktop \
      --replace-fail 'Exec=Hermes.WebUI.Desktop' "Exec=$out/bin/hermes-desktop" \
      --replace-fail 'Icon=Hermes.WebUI.Desktop' "Icon=hermes-desktop" || true
  '';

  meta = with lib; {
    description = "Official native Tauri 2 desktop application for Hermes WebUI";
    homepage = "https://github.com/hermes-webui/hermes-desktop-rust";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hermes-desktop";
  };
}
