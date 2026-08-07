---
name: security-review
description: Security-focused review of code, configuration, and system boundaries. Use for auth-sensitive code, data handling, API exposure, or any change that touches a trust boundary. Produces a threat assessment with prioritized findings. Load before merging security-relevant changes.
---

# Security Review

Security review is not a checklist. It is a structured analysis of how a change affects the system's trust model — what an attacker could do with the new surface, and whether existing mitigations hold. Every change that touches a trust boundary must pass security review.

## Theoretical Foundation

- **STRIDE Threat Modeling** (Microsoft, Kohnfelder & Garg 1999): Enumerate threats by category — Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege. Each category maps to a specific violated property.
- **Least Privilege**: Every component, process, and user should operate with the minimum permissions necessary. If the change introduces a permission, justify why it cannot be smaller.
- **Defense in Depth**: A single control can fail. Sensitive paths require layered controls — don't rely on "the firewall will stop it" when the code itself could prevent the exploit.
- **OWASP Top 10**: The canonical catalog of web application security risks (injection, broken auth, sensitive data exposure, XSS, broken access control, security misconfiguration, etc.). Every web-facing code change must be checked against these categories.
- **Trust Boundaries**: The line between trusted and untrusted data. Every function that receives data from a user, an external API, a file, or a network crosses a trust boundary. Validate, sanitize, and constrain at the boundary — not deep in the call stack.

## Prerequisite

Load **`systematic-exploration`** first if the change's full surface is unknown — you must map every trust boundary before assessing threats.

## Trigger

Load this skill when:
- Changes touch authentication, authorization, session management, or API keys
- Code processes user input, file uploads, or external data
- New APIs, endpoints, or network listeners are introduced
- Database queries, serialization, or deserialization are modified
- Secrets management, cryptography, or key handling is involved
- Configuration changes open new ports, services, or access patterns
- `code-review` identifies security-relevant surface area
- The user explicitly requests security review

Do NOT load this skill for:
- Pure refactoring with zero behavioral change (verified by characterization tests)
- Documentation-only changes
- Changes with no trust boundary exposure (e.g., internal refactoring of a rendering function)

## Subagent Delegation

For changes touching 2+ trust boundaries, dispatch a `security-reviewer` subagent with fresh context:

```
task({
  subagent_type: "security-reviewer",
  prompt: "Security review of [change]. Specification: [ref]. Trust boundaries: [list]. Assets at risk: [list]. Previous security decisions: [ADR refs if any].",
  description: "Security review [change]"
})
```

The security-reviewer has no prior knowledge of the implementation — it attacks the system as an adversary would, with zero trust in the developer's assumptions.

## Process

### Step 1: Identify Assets and Trust Boundaries

```
Assets (what must be protected):
- [Data: PII, credentials, internal state, business logic]
- [Infrastructure: compute resources, network access, secrets store]

Trust boundaries crossed by this change:
- [Boundary: user input → validation]
- [Boundary: API client → server]
- [Boundary: database query → execution]
- [Boundary: file system → process]
```

### Step 2: STRIDE Threat Enumeration

For each trust boundary, enumerate threats:

| Boundary | Spoofing | Tampering | Repudiation | Info Disclosure | DoS | Elevation |
|---|---|---|---|---|---|---|
| [boundary] | [threat or N/A] | ... | ... | ... | ... | ... |

Every cell must be either a specific threat or explicitly "N/A" with a one-sentence justification.

### Step 3: Assess Existing Mitigations

```
For each identified threat:
- Existing mitigation: [what already protects against this]
- Residual risk after mitigation: [HIGH | MEDIUM | LOW]
- Recommendation if residual risk is HIGH or MEDIUM: [concrete action]
```

A missed mitigation is a finding. An inadequate mitigation is a finding. "The firewall will stop it" is not a mitigation unless the firewall rule is verified.

### Step 4: Prioritize Findings

```
BLOCKER (must fix before merge — data loss, privilege escalation, exposed secret):
- [file:line] Specific vulnerability with exploit path

WARNING (should fix — weak control, subtle leak, hardening opportunity):
- [file:line] Specific weakness with improvement path

OBSERVATION (low risk — defense-in-depth suggestion, documentation gap):
- [file:line] Specific observation
```

### Step 5: Verify Against Specification

Cross-reference any security requirements from the specification:

- If the spec says "only authenticated users" → verify every code path enforces auth
- If the spec says "data encrypted at rest" → verify encryption is applied, not assumed
- If the spec says "rate-limited" → verify the limit is enforced, not just configured

## Evidence

After completing this skill:
- [ ] Trust boundaries mapped
- [ ] STRIDE matrix completed (one per boundary)
- [ ] Mitigations assessed with residual risk levels
- [ ] Findings prioritized (BLOCKER | WARNING | OBSERVATION)
- [ ] Specification security requirements verified against implementation

## Exit Gate

Security review is complete when:
- Every trust boundary has been enumerated
- Every STRIDE cell has a threat or "N/A" justification
- Every HIGH or MEDIUM residual risk has a concrete recommendation
- BLOCKERS have been reported (the fix is the developer's responsibility)

## Handoff

After this skill:
- **`code-review`** — incorporate security findings into the review verdict
- If BLOCKERS: the spec or implementation must be revised before merge

## Anti-Patterns

- **Checklist theatre**: Running through OWASP categories without tracing actual code paths. "We checked for SQL injection" — did you trace every user input to every database call?
- **Mitigation optimism**: "The ORM prevents SQL injection." ORMs have raw query methods. Verify, don't assume.
- **Magic-string trust**: Checking `if (role == "admin")` without verifying the role claim source. Auth is complete only when the chain from credential to permission is verified end-to-end.
- **Perimeter-only thinking**: "The firewall/VPN/network policy handles it." Zero-trust: assume the perimeter is compromised. Verify controls at the application layer.
- **Fear-driven over-engineering**: Demanding TLS, client certs, HMAC signing, and audit logging for an internal health check endpoint. Right-size controls to the asset's value.
- **Ignoring secret handling**: API keys, tokens, and passwords in logs, error messages, or client-accessible code. A secret in a log message is no longer a secret.
