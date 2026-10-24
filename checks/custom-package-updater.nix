# The updater's own test suite, wired to the script it tests. The app lives in `apps/`, so its test
# does too; this check exists because nothing else would run it.
{ pkgs, ... }:
pkgs.runCommandLocal "custom-package-updater-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      python3
      jq
      gawk
    ];
  }
  ''
    python3 ${../apps/update-custom-packages/tests/test_github_source.py} ${../apps/update-custom-packages/update-custom-packages.sh}
    touch $out
  ''
