# Codex agent runtime. The profile routes its GPT-5.4 fallback through it, and OpenClaw reports a
# doctor warning when a route selects Codex while the plugin is disabled.
{
  npm = "@openclaw/codex";
  contribution = "harness";
}
