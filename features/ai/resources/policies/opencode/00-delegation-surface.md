# OpenCode delegation surface

- Use OpenCode's native `subagent` tool and a `subagent` agent for delegated work. The child starts with
  fresh context and its own configured permissions.
- OpenChamber's agent tool is the user's dispatch and control surface. It is not a second
  delegation mechanism and does not create another coordinator.
- Do not invent an agent role, model, provider or timeout just to make a tool available. Use an
  existing configured agent; if none fits, report the gap.
- Agent permissions, models and step limits belong in configuration. Instructions describe
  behaviour, not credentials or hard-coded model names.
