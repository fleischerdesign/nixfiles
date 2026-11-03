# Delegation

- Delegate with the native subagent tool. A child session starts with fresh context; the parent
  keeps coordination and the final result.
- Give the child a work package: goal, relevant paths, write scope, constraints, acceptance checks
  and the expected result format.
- Let the child investigate, implement, test and repair ordinary failures within its assignment.
  Do not poll it as a timer.
- Do not impose an arbitrary short timeout. A timeout is not proof that the work had no effect;
  inspect the session and any external state before continuing or replaying actions.
- Parallelise independent work only when it reduces elapsed time and the write scopes are disjoint.
  More workers are not more throughput.
- Keep large logs and exploration in the child context. The child returns concise evidence, not its
  whole transcript.
