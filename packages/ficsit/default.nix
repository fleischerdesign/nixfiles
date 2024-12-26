{
  stdenv,
  fetchurl,
}:

let
  version = "0.6.0";
  pname = "ficsit";

  src = fetchurl {
    url = "https://github.com/satisfactorymodding/ficsit-cli/releases/download/v${version}/ficsit_linux_amd64";
    sha256 = "sha256-PN9IqGZSLgug6YgAgNKMmSX0VlgBGc/Aj1YqkPHqLRY=";
  };

in
stdenv.mkDerivation rec {
  inherit version pname src;

  sourceRoot = ".";

  installPhase = ''
    install -m755 -D ficsit_linux_amd64 $out/bin/ficsit
  '';
}