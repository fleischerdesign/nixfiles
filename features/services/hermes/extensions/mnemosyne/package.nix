# features/services/hermes/extensions/mnemosyne/package.nix — Mnemosyne packages
#
# Builds two Python packages from PyPI:
#   mnemosyne-memory   Vector memory database (sqlite-vec, fastembed, numpy)
#   mnemosyne-hermes   CLI tool for managing Mnemosyne databases
#
# Fastembed is pinned to the vanilla nixpkgs version — no pillow override
# needed since we no longer bridge a uv2nix venv with nixpkgs PYTHONPATH.
{ python3Packages }:

let
  pythonPackages = python3Packages;

  memory = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-memory";
    version = "3.8.0";
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_memory";
      inherit version;
      hash = "sha256-xN6P6HYd8gawnU2bFZXozyionpJeaLTTNAGBuAhRrGY=";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = with pythonPackages; [
      sqlite-vec
      fastembed
      numpy
    ];
    doCheck = false;
  };

  hermes = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-hermes";
    version = "0.2.0";
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_hermes";
      inherit version;
      hash = "sha256-iWlGvajMQg/GE8VdJ7VTNAzxILRNUIS00/ArYGDlhbM=";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = [ memory ];
    doCheck = false;
    meta.mainProgram = "mnemosyne-hermes";
  };

in
{
  inherit memory hermes;
}
