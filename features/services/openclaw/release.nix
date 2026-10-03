# The OpenClaw release this fleet runs, declared where it is reviewed.
#
# The pinned flake owns packaging and plugin locks. `build.nix` asserts its source release matches
# this descriptor; version changes must therefore be reviewed alongside the input update.
{
  releaseVersion = "2026.9.5";
  releaseRev = "ec9c1a13db8938e5a3eaa51fca2e981cde2395a9";
}
