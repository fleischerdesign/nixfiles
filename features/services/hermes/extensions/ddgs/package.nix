# features/services/hermes/extensions/ddgs/package.nix — DDGS package
#
# DuckDuckGo Search Python package built from PyPI. Provides the
# 'ddgs' module used by hermes-agent for web search functionality.
{ python3Packages }:

let
  pythonPackages = python3Packages;

in
pythonPackages.buildPythonPackage rec {
  pname = "ddgs";
  version = "9.14.4";
  src = pythonPackages.fetchPypi {
    inherit pname version;
    hash = "sha256-97EYorcJqenASh3Kbpa5jCXU36yhpLCiRNdEVPzKSO8=";
  };
  pyproject = true;
  build-system = [ pythonPackages.setuptools ];
  propagatedBuildInputs = with pythonPackages; [
    click
    primp
    lxml
    httpx
    fake-useragent
  ];
  doCheck = false;
}
