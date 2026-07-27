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
      sha256 = "sha256-c4de8fe8761df206b09d4d9b1595e8cf28a89e925e68b4d3340181b80851ac66";
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
      sha256 = "sha256-896946bda8cc420fc613c55d27b553340cf120b44d5084b4d3f02b6060e585b3";
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
