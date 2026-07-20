# overlays/fix/patool/default.nix
# TEMPORARY FIX — remove when upstream PR is merged.
# patool 4.0.0 tests expect format-specific helper functions
# (list_bzip2, list_lzma, list_xz, list_lzip) that the
# new py_tarfile/tar modules no longer export.
#
# Upstream fix: https://github.com/NixOS/nixpkgs/pull/540742 (merged 2026-07-11)
# fixes file's landlock sandbox → patool's MIME detection.
# patool tests still fail in Nix build sandbox after the fix,
# so doCheck = false remains the workaround until resolved.
#
# Impact: blocks bottles (Wine prefix manager) on desktop hosts.
_final: prev: {
  python3Packages = prev.python3Packages.overrideScope (
    _pyFinal: pyPrev: {
      patool = pyPrev.patool.overridePythonAttrs (_: {
        doCheck = false;
      });
    }
  );
}
