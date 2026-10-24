# `nix fmt` is optional locally, so the formatter the repository declares (`formatter.<system>`)
# also runs here: a file it would change fails the build instead of being caught only by a hook that
# may not be installed. treefmt formats in place, so the tree is copied and the copy is compared to
# the original - the check measures the declared formatter, not a second spelling of it.
{ pkgs, ... }:
pkgs.runCommandLocal "nixfmt-check"
  {
    nativeBuildInputs = [
      pkgs.nixfmt-tree
      pkgs.diffutils
    ];
  }
  ''
    cp -r --no-preserve=mode ${../.} src
    (
      cd src
      treefmt --no-cache --tree-root . --walk filesystem
    )
    if ! diff -r ${../.} src >&2; then
      echo "nix fmt would reformat the files above" >&2
      exit 1
    fi
    touch $out
  ''
