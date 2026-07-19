# features/services/hermes-agent/python-packages.nix
{
  pkgs,
  fastembed-override ? pkgs.python312Packages.fastembed,
}:

let
  pythonPackages = pkgs.python312Packages;

  ddgs = pythonPackages.buildPythonPackage rec {
    pname = "ddgs";
    version = "9.14.4";
    src = pythonPackages.fetchPypi {
      inherit pname version;
      sha256 = "f7b118a2b709a9e9c04a1dca6e96b98c25d4dfaca1a4b0a244d74454fcca48ef";
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
  };

  mnemosyne-memory = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-memory";
    version = "3.8.0";
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_memory";
      inherit version;
      sha256 = "c4de8fe8761df206b09d4d9b1595e8cf28a89e925e68b4d3340181b80851ac66";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = with pythonPackages; [
      sqlite-vec
      fastembed-override
      numpy
    ];
    doCheck = false;
  };

  mnemosyne-hermes = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-hermes";
    version = "0.2.0";
    src = pythonPackages.fetchPypi {
      pname = "mnemosyne_hermes";
      inherit version;
      sha256 = "896946bda8cc420fc613c55d27b553340cf120b44d5084b4d3f02b6060e585b3";
    };
    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    propagatedBuildInputs = [
      mnemosyne-memory
    ];
    doCheck = false;
  };
in
{
  inherit ddgs mnemosyne-memory mnemosyne-hermes;
}
