# Documentation

This directory is the specification of the system as it **is**. It is not a plan, not a migration
diary, and not a to-do list: those have an expiry, and a specification that carries them describes two
states at once. History belongs in a commit message.

Two files stay in the repository root because tools and conventions expect them there:
[`../README.md`](../README.md) (entry point) and [`../AGENTS.md`](../AGENTS.md) (instructions for
agentic contributors). The repository layout is documented in `AGENTS.md`, once.

## The map

| Question | Document |
|---|---|
| What is this system - hosts, zones, planes, the mesh, DNS, contracts? | [architecture.md](architecture.md) |
| Who is a user, what is a service account, how do access, secrets and the security model work? | [identity.md](identity.md) |
| How do I deploy, reach a host, verify a change, recover a host I locked myself out of? | [operations.md](operations.md) |
| Which desktop runs, who owns the session, where do user settings and remote mounts live? | [desktop.md](desktop.md) |
| What are the microcontrollers, the access point, the router? | [embedded.md](embedded.md) |
| What do the interfaces look like, which tokens and typography? | [design.md](design.md) |

## How to read these

- **Architecture first.** It defines the vocabulary - host, zone, plane, contract, scope - that the
  others use without redefining it.
- **Names are derived, never maintained.** An FQDN is a function of the topology and the contracts
  ([architecture.md](architecture.md) §5). Where a document and the code disagree, the code is right
  and the document is a bug.
- **Claims carry their evidence.** A statement is measured (the command is named) or asserted (the
  invariant is named). Statements without either are opinions.

## Conventions

| | |
|---|---|
| Language | English, throughout |
| Diagrams | ASCII, in the document that owns the concept |
| File names | lowercase, `noun.md` |
| Scope | one document per question; a fact that appears twice is a bug waiting to disagree |
| Status | a specification describes the present; history belongs in a commit message |
