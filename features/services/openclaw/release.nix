# The OpenClaw release this fleet runs, declared where it is reviewed.
#
# The flake input pins the packaging machinery (and the generated plugin locks); the version, tag
# commit and runtime-plugin version of the release actually used are declared here. `build.nix`
# resolves the input's plugin packages against this descriptor, so a version change is a visible
# change in this repository rather than a silent move of a floating input. The plugin catalogue lives
# in `plugins.nix`; it is keyed by the identifier a profile may name.
{
  releaseVersion = "2026.9.5";
  releaseTag = "v2026.9.5";
  releaseRev = "ec9c1a13db8938e5a3eaa51fca2e981cde2395a9";
  runtimePluginVersion = "2026.9.5";
}
