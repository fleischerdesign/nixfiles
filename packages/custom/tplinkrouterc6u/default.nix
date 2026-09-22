# packages/custom/tplinkrouterc6u/default.nix
# Python package derivation for tplinkrouterc6u (TP-Link router & range extender API client)
{
  python3Packages,
  fetchPypi,
}:

python3Packages.buildPythonPackage rec {
  pname = "tplinkrouterc6u";
  version = "5.34.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-EYsex7AjQRcU8cT45V1TraiQGb7qHDPfBhuB7mOT5yY=";
  };

  build-system = [
    python3Packages.setuptools
  ];

  dependencies = with python3Packages; [
    requests
    pycryptodome
    macaddress
  ];

  doCheck = false;

  meta = {
    description = "TP-Link Router API client supporting RE330, Archer, and Mercusys hardware";
    homepage = "https://github.com/AlexandrErohin/TP-Link-Archer-C6U";
  };
}
