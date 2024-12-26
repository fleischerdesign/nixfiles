{
  lib,
  appimageTools,
  fetchurl,
}:

let
  version = "3.0.3";
  pname = "smm";
  name = "${pname}-${version}";

src = fetchurl {
    url = "https://github.com/satisfactorymodding/SatisfactoryModManager/releases/download/v${version}/SatisfactoryModManager_linux_amd64.AppImage";
    hash = "sha256-EsTF7W1np5qbQQh3pdqsFe32olvGK3AowGWjqHPEfoM=";
  };

appimageContents = appimageTools.extractType1 { inherit name src; };
in
appimageTools.wrapType1 {
  inherit name src;

extraInstallCommands = ''
    mv $out/bin/${name} $out/bin/${pname}
    install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${appimageContents}/usr/share/icons $out/share
  '';
}