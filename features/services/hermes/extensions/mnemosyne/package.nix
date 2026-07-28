# features/services/hermes/extensions/mnemosyne/package.nix — Mnemosyne packages
#
# Builds two Python packages from PyPI:
#   mnemosyne-memory   Vector memory database (sqlite-vec, fastembed, numpy)
#   mnemosyne-hermes   CLI tool for managing Mnemosyne databases
#
# Versions and hashes are managed via manifest.json. Run
#   nix run .#update-custom-packages
# to check for upstream updates.
{ python3Packages }:

let
  pythonPackages = python3Packages;
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);

  memory = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-memory";
    version = manifest.memoryVersion;
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_memory";
      inherit version;
      hash = manifest.memoryHash;
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
    version = manifest.hermesVersion;
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_hermes";
      inherit version;
      hash = manifest.hermesHash;
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
