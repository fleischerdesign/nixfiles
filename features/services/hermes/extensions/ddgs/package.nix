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
    sha256 = "sha256-f7b118a2b709a9e9c04a1dca6e96b98c25d4dfaca1a4b0a244d74454fcca48ef";
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
