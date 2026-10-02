# Fixture: an unknown field must fail the loader, so a plugin cannot grow behavior silently.
{
  npm = "@example/unknown-field";
  contribution = "tool";
  settings = { };
}
