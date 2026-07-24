# overlays/fix/cheetah3/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase failure.
#
# cheetah3 fails importlib.metadata check during Python 3.14 build phase:
# "importlib.metadata.PackageNotFoundError: No package metadata was found for cheetah3"
#
# Impact: Blocks SABnzbd service (features/services/sabnzbd) on host strummer.
# Remove when upstream nixpkgs fixes python314Packages.cheetah3 metadata checks.
_final: prev: {
  python314Packages = prev.python314Packages.overrideScope (
    _pyFinal: pyPrev: {
      cheetah3 = pyPrev.cheetah3.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    }
  );
  python3Packages = prev.python3Packages.overrideScope (
    _pyFinal: pyPrev: {
      cheetah3 = pyPrev.cheetah3.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    }
  );
  python3 = prev.python3.override {
    packageOverrides = _finalPy: pyPrev: {
      cheetah3 = pyPrev.cheetah3.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    };
  };
}
