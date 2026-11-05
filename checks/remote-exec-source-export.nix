# A remote attempt must start from exactly the source the worktree holds. The
# failure this catches: an export that drops a dirty or staged file, lets a
# personal global ignore hide an input, drops a nested negation, loses the
# executable bit or a safe symlink, ships `.git`/object-store references, mutates
# the parent HEAD/index, or publishes an unverified tree.
#
# The check runs the package's own fixture suite: real Git repositories, the real
# source selector, the real manifest verifier, and a local executor round trip.
{ pkgs, self, ... }:
self.packages.${pkgs.stdenv.hostPlatform.system}.remote-exec.passthru.tests
