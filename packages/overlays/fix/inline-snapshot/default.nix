# overlays/fix/inline-snapshot/default.nix
# TEMPORARY FIX — python3.12 inline-snapshot 0.32.5 tests broken upstream.
# Docs tests assert exact line numbers in code generation output.
# Remove when upstream publishes fixed tests.
#
# Applied via overrideScope at python312Packages level to propagate into
# internal Python package scope (used by Hermes Agent and dependencies).
_final: prev: {
  python312Packages = prev.python312Packages.overrideScope (
    _pyFinal: pyPrev: {
      inline-snapshot = pyPrev.inline-snapshot.overridePythonAttrs (_: {
        doCheck = false;
      });
    }
  );
}
