{
  stdenv,
  fetchurl
}:

let
  version = "0.6.0";
  pname = "ficsit";

  src = fetchurl {
    url = "https://github.com/satisfactorymodding/ficsit-cli/releases/download/v${version}/ficsit_linux_amd64";
    sha256 = "sha256-7YYllR3zKaEi8WDGQrijUMR3lMebjBpF/go9/1LK/P0=";
  };

in
stdenv.mkDerivation{
  inherit version pname src;

  phases = [ "installPhase" ];

  installPhase = ''
    install -D $src $out/bin/${pname}
  '';
}