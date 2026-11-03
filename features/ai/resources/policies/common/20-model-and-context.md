# Model and context budget

- Use the model configured for the session and for the subagent. Model choice, provider choice and
  execution limits are configuration; do not hard-code them in instructions or switch them on your
  own.
- Use a stronger model only when the task needs its judgment. Routine execution stays on the
  configured default.
- Keep the child context isolated and sufficient. Fork the conversation only when its history is
  genuinely necessary.
- Do not treat a generated file as a working configuration without the runtime check that consumes
  it.
