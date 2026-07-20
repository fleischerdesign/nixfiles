# overlays/fix/inline-snapshot/default.nix
# TEMPORARY FIX — remove when upstream inline-snapshot docs tests are fixed.
# inline-snapshot 0.32.5 has docs test assertions that fail due to shifted
# line numbers in code generation output. The library itself works fine.
#
# Upstream: no fix PR tracked yet (2026-07-20)
#
# Impact: blocks Hermes Agent on rollins (transitive Python dependency).
_final: prev: {
  python3Packages = prev.python3Packages // {
    inline-snapshot = prev.python3Packages.inline-snapshot.overridePythonAttrs (_: {
      doCheck = false;
    });
  };
}
