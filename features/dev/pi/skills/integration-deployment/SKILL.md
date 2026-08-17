---
name: integration-deployment
description: Build, stage, deploy, and verify a change in a production-like environment. Use after code-review, documentation-consistency, and release-management (if versioned) — before declaring the change "done." Produces a verified deployment with smoke tests and a documented rollback plan.
---

# Integration & Deployment

Code that passes review in a development environment has not been verified. Integration tests run against real dependencies. Staging exercises real configuration. Production is where edge cases become incidents. Deployment verification is the last gate before "done."

## Theoretical Foundation

- **Continuous Delivery** (Humble & Farley 2010): Every change should be in a deployable state. The pipeline — build, test, stage, deploy — must be repeatable, reliable, and fast enough that deployment is a non-event, not a ceremony.
- **Smoke Tests** (Boehm 1979, *Software Engineering Economics*): A minimal set of tests that verify the deployment is alive and functional — not the full test suite (which runs earlier in CI), but the critical path: can users log in? Does the API respond? Are dependencies reachable?
- **Blue-Green / Canary Deployment**: New code runs alongside old code, with a fraction of traffic routed to the new version. If the new version fails, traffic shifts back. Verification happens under REAL traffic before 100% rollout.
- **Rollback-Ready Deployments**: Every deploy must have a documented and tested rollback path. If rollback takes longer than deploy, the deploy is riskier than the verification can justify. The rollback should be faster than the mean time to detect (MTTD).

## Trigger

Load this skill when:
- Code review has approved the change
- Documentation consistency has passed
- Release management has produced the version, changelog, and tag (if this is a versioned release)
- The change is ready to be deployed
- Performance verification has passed (if criteria existed)
- `orchestration` signals the deployment phase

Do NOT load this skill for:
- Changes that don't require deployment (documentation, pure analysis)
- PRs that haven't passed code review
- Local-only development (unless verifying build artifact)

## Process

### Step 1: Discover Deployment Method

Read the project's deployment configuration to determine the method:

```
Deployment method:
- [file] → [method]
- flake.nix → nixos-rebuild switch --flake .#<host> or deploy .#<host>
- docker-compose.yml → docker compose up -d
- Dockerfile + CI → docker build && push && deploy
- Makefile deploy target → make deploy
- package.json deploy script → npm run deploy

If no deployment method is documented: flag as BLOCKER. You cannot deploy without a known, repeatable method.
```

### Step 2: Build the Artifact

```
1. Build clean: from the approved commit/tag, never from a dirty working directory
2. Verify build: the artifact is valid (hash, size, integrity check)
3. Verify dependencies: all pinned versions are resolved
4. Document artifact: path, hash, version, build timestamp
```

### Step 3: Deploy to Staging

```
1. Deploy using the discovered method
2. Verify deployment: health check, version endpoint, process/container running
3. Run smoke tests:
   - Critical path 1: [description] → PASS/FAIL
   - Critical path 2: [description] → PASS/FAIL
   - Critical path 3: [description] → PASS/FAIL
4. If any smoke test fails: DO NOT proceed to production. Roll back staging and report.
```

### Step 4: Deploy to Production

```
1. Pre-deploy checklist:
   - [ ] Staging smoke tests passed
   - [ ] Rollback plan documented and tested
   - [ ] Monitoring/alerting configured for the change (if applicable)
   - [ ] Database migrations applied (if applicable) — and verified
   - [ ] Dependencies healthy and reachable

2. Deploy:
   - Canary: route N% of traffic → verify → increase → 100%
   - Blue-green: deploy to inactive → switch traffic → verify → decommission old
   - Direct: deploy → verify immediately (only for low-risk changes)

3. Post-deploy verification:
   - Health check: [endpoint/command] → PASS/FAIL
   - Critical smoke test: [test] → PASS/FAIL
   - Monitor for: errors, latency spikes, memory leaks, connection drops
```

### Step 5: Monitor and Rollback Plan

```
Monitoring (first 5-15 minutes post-deploy):
- Error rate: [baseline vs. current]
- Latency p95: [baseline vs. current]
- Resource usage: [CPU, memory, connections]
- Application logs: [error frequency]

Rollback decision: if any monitored metric degrades beyond threshold, execute rollback:
1. [Rollback command or procedure]
2. Verify rollback: health check → PASS
3. Notify: [who needs to know]
4. Post-mortem: what happened? (→ load `post-mortem` skill)

Rollback threshold: [define before deploying — e.g., "error rate > 1% above baseline for 2 consecutive minutes"]
```

## Evidence

After completing this skill:
- [ ] Deployment method documented
- [ ] Artifact built and verified
- [ ] Staging deployment: smoke tests PASS
- [ ] Production deployment verified (or rollback executed)
- [ ] Monitoring confirms health (or rollback triggered)
- [ ] Rollback plan documented and tested

## Exit Gate

Deployment is complete when:
- The change is running in production and verified healthy
- Monitoring shows no degradation after the observation window
- OR: a rollback has been executed cleanly and a post-mortem is scheduled

## Handoff

After this skill:
- Successful deploy: task is **done**. No further skills.
- Rollback: **`post-mortem`** — analyze the failure
- Verified deploy with no rollback: update documentation, close spec, archive artifacts

## Anti-Patterns

- **Deploy-and-pray**: Pushing to production without smoke tests or monitoring. "It works on staging" is a hypothesis, not a verification.
- **No rollback plan**: "We'll fix it if it breaks." Mean time to repair (MTTR) without a plan is unbounded. A rollback should be faster than a fix.
- **Friday deploy**: Deploying on Friday without weekend monitoring coverage. If nobody is watching the monitors, the deployment is unverified during the riskiest window.
- **Manual-only deploy**: "Bob has the deploy script on his machine." If the deploy method is not in version control, it is not repeatable and Bob is a single point of failure.
- **Smoke tests as afterthought**: Adding smoke tests after the deployment "because the pipeline is red." Smoke tests must be defined BEFORE deployment — they are the acceptance gate, not a debugging tool.
- **Configuration drift**: Staging configuration differs from production in a way that matters (memory limits, connection pools, network topology). A change that works in staging can fail in production because the environment is different, not because the code is wrong.
