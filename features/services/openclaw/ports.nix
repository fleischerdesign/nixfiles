# The ports OpenClaw derives internally from the gateway port, and the offsets this feature applies.
#
# OpenClaw's own derivation (`extensions/browser/src/config/port-defaults.ts`): the Browser Control
# service is `gateway + 2`, and its managed Chrome CDP allocation band is `gateway + 11` through
# `gateway + 110`. One definition, read by the feature and by every check, so an offset is never
# restated as a literal in a second place.
{
  # MCP Apps (the sandbox host) defaults to `gateway + 1` in OpenClaw; this feature relies on that.
  apps = 1;
  # Browser Control, derived by OpenClaw and therefore reserved whether or not it is enabled.
  browserControl = 2;
  # The managed Chrome CDP allocation band.
  browserCdpStart = 11;
  browserCdpEnd = 110;
  # A mesh-local publishing router deliberately far outside the OpenClaw-derived band. It is a
  # feature port, not an OpenClaw port, and only needs to stay clear of the derived ranges above.
  publishing = 2048;
}
