# Upstream's Nix desktop build runs with `--ignore-scripts`, so `npm run postinstall` never
# executes and `patches/@gorhom+bottom-sheet+5.2.14.patch` is never applied. The renderer then has
# no `BottomSheetModalInternalProvider`, and opening any chat dies on minified React error #130
# (getpaseo/paseo#7673, diagnosed upstream).
#
# The overlay is where this belongs: the feature keeps asking for `pkgs.paseo-desktop` and does not
# carry knowledge of a build defect, and the day upstream applies the patch the overlay is deleted
# without touching the module.
#
# The package still comes from the flake input, so the version tracks `main` as everywhere else;
# only the missing build step is added.
paseo: _final: prev: {
  paseo-desktop = paseo.packages.${prev.stdenv.hostPlatform.system}.desktop.overrideAttrs (previous: {
    preBuild = (previous.preBuild or "") + "\nnpm run postinstall";
  });
}
