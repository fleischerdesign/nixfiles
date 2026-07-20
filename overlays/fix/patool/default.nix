# overlays/fix/patool/default.nix
# TEMPORARY FIX — remove when upstream PR is merged.
# patool 4.0.0 tests expect format-specific helper functions
# (list_bzip2, list_lzma, list_xz, list_lzip) that the
# new py_tarfile/tar modules no longer export.
#
# Upstream status: no fix PR exists yet (2026-07-20).
# Last checked nixpkgs-unstable rev a16c3fde2ffe — patool 4.0.5
# still has the same broken test assertions.
#
# Impact: blocks bottles (Wine prefix manager) on desktop hosts.
_final: prev: {
  python3Packages = prev.python3Packages // {
    patool = prev.python3Packages.patool.overridePythonAttrs (_: {
      doCheck = false;
    });
  };
}
