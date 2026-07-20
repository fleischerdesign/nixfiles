# overlays/fix/python-tests/default.nix
# TEMPORARY FIX — python3.12 inline-snapshot 0.32.5 tests broken upstream.
# Docs tests assert exact line numbers in code generation output.
# Remove when upstream publishes fixed tests.
#
# Applied at python312Packages level because Hermes Agent uses Python 3.12
# specifically, not the nixpkgs-unstable default Python version.
_final: prev: {
  python312Packages = prev.python312Packages // {
    inline-snapshot = prev.python312Packages.inline-snapshot.overridePythonAttrs (_: {
      doCheck = false;
    });
  };
}
