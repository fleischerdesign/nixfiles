{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "openchamber-desktop";
  version = "2.0.1";
  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v2.0.1/OpenChamber-2.0.1-linux-x86_64.AppImage";
    hash = "sha256-tPa29joQMqTXej6kWcavz9ckaKllMAu3b6o9Duf7ppg=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/usr/share/icons/hicolor/scalable/openchamber.svg \
      "$out/share/icons/hicolor/scalable/apps/openchamber.svg"
  '';

  meta = {
    description = "OpenChamber desktop workspace";
    homepage = "https://openchamber.dev";
    license = lib.licenses.mit;
    mainProgram = "openchamber-desktop";
    platforms = [ "x86_64-linux" ];
  };
}
