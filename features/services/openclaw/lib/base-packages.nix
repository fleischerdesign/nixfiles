# features/services/openclaw/lib/base-packages.nix
# The execution baseline shared by every OpenClaw process on the fleet - gateway instances and
# companion nodes alike. One list, two consumers: without it the gateway and the node module carry
# the same 24 packages twice and drift apart the first time one side gains a tool.
#
# `direnv` is in the list on purpose: the per-repository toolchain (node, compiler, formatter) comes
# from each repository's own `flake.nix` via `use flake`, so the machine only needs the loader.
# Node and npm are deliberately absent - a repository that pins them declares them itself.
{ pkgs }:
[
  pkgs.nix
  pkgs.git
  pkgs.gh
  pkgs.ripgrep
  pkgs.ripgrep-all
  pkgs.fd
  pkgs.procps
  pkgs.curl
  pkgs.gnutar
  pkgs.gzip
  pkgs.zip
  pkgs.unzip
  pkgs.jq
  pkgs.yq-go
  pkgs.sqlite
  pkgs.poppler-utils
  pkgs.imagemagick
  pkgs.pandoc
  pkgs.ast-grep
  pkgs.universal-ctags
  pkgs.tokei
  pkgs.lsof
  pkgs.moreutils
  pkgs.nvd
  pkgs.nix-diff
  pkgs.direnv
]
