# Documentation

This directory is the specification of the system as it **is**. It is not a plan, not a migration
diary, and not a to-do list: those have an expiry, and a specification that carries them describes two
states at once.

Two files stay in the repository root because tools and conventions expect them there:
[`../README.md`](../README.md) (entry point) and [`../AGENTS.md`](../AGENTS.md) (instructions for
agentic contributors).

## The map

| Question | Document |
|---|---|
| What is this system, which machines does it run on, how do they talk to each other? | [architecture.md](architecture.md) |
| What may a name look like, which plane does it live in, who owns it? | [naming.md](naming.md) |
| How do I deploy, reach a host, verify a change, recover a host I locked myself out of? | [operations.md](operations.md) |
| How do we work here - what counts as verified, what are the failure patterns? | [practices.md](practices.md) |
| Who is a user, what is a service account, how does authentication and authorisation work? | [identity.md](identity.md) |
| What is the security model, layer by layer? | [security.md](security.md) |
| What are the microcontrollers, the access point, the router - and how are they configured? | [embedded.md](embedded.md) |
| What do the interfaces look like, which tokens and typography? | [design.md](design.md) |

## How to read these

- **Architecture first.** It defines the vocabulary - zone, plane, contract, scope - that the other
  documents use without redefining it.
- **Names are derived, never maintained.** [`naming.md`](naming.md) is normative: an FQDN is a function
  of the topology and the contracts. Where this documentation and the code disagree, the code is right
  and the document is a bug.
- **Claims carry their evidence.** Where a statement says "measured", it names the command and the date.
  Where it says "asserted", it names the invariant that enforces it at evaluation time. Statements
  without either are opinions and should be read as such.
- **Everything in English.** Code, comments, commits and documentation - verified, not intended:
  no document in this directory contains German prose any more. A specification that changes language
  mid-draft is one that will be half-updated, and the half that lags is the half nobody notices.

## Conventions

| | |
|---|---|
| Language | English, throughout |
| Diagrams | ASCII, in the document that owns the concept |
| File names | lowercase, `noun.md` - the name says what the file is, not what it was for |
| Cross-references | relative links between siblings, `docs/<name>.md` from the root |
| Status | a specification describes the present; history belongs in a commit message, not a section |
