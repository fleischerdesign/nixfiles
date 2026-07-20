# overlays/fix/patool/default.nix
# TEMPORARY FIX — remove when upstream PR is merged.
# patool 4.0.0 tests expect format-specific helper functions
# (list_bzip2, list_lzma, list_xz, list_lzip) that the
# new py_tarfile/tar modules no longer export.
#
# Upstream PR: https://github.com/NixOS/nixpkgs/pull/540742
# Bug tracked since ~2026-07-12
#
# Impact: blocks bottles (Wine prefix manager) on desktop hosts.
_final: prev: {
  python3Packages = prev.python3Packages // {
    patool = prev.python3Packages.patool.overridePythonAttrs (_: {
      doCheck = false;
    });
  };
}
