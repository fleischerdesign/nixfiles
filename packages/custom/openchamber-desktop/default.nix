{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "openchamber-desktop";
  version = "2.3.3";
  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v2.3.3/OpenChamber-2.3.3-linux-x86_64.AppImage";
    hash = "sha256-Xy1JH8By9ikyeVrYdc9fIlo7z4MS6YTdLnJzsCF9/Z4=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/usr/share/icons/hicolor/512x512/apps/openchamber.png \
      "$out/share/icons/hicolor/512x512/apps/openchamber.png"
  '';

  meta = {
    description = "OpenChamber desktop workspace";
    homepage = "https://openchamber.dev";
    license = lib.licenses.mit;
    mainProgram = "openchamber-desktop";
    platforms = [ "x86_64-linux" ];
  };
}
