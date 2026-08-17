---
name: performance-verification
description: Verify that code meets its performance criteria. Use when a specification includes latency, throughput, or resource constraints. Produces statistically valid benchmark evidence — not gut feelings, not "it feels fast."
---

# Performance Verification

Performance is a requirement, not a feeling. When a spec says "p95 < 200ms for 1000 concurrent requests," the implementation must be verified against that threshold with evidence that would survive peer review. "It seems fast" is not verification.

## Theoretical Foundation

- **Statistical Rigor in Benchmarking** (Mytkowicz et al. 2009, *Producing Wrong Data Without Doing Anything Obviously Wrong*): Measurement is sensitive to environment noise, warm-up effects, garbage collection, and benchmark design. A single run says nothing. Use multiple trials, report distributions (not just mean), and control for confounding variables.
- **Latency Numbers Every Programmer Should Know** (Dean 2009): Orders of magnitude matter. L1 cache reference (1ns) vs. main memory (100ns) vs. SSD (10-100µs) vs. disk (1-10ms) vs. network round trip (1-100ms). The verification method must be meaningfully more precise than the threshold being measured.
- **Tail Latency** (Dean & Barroso 2013, *The Tail at Scale*): The 99th percentile user experience is the experience of the most patient users. Optimizing for mean latency hides the tail. Specs that provide only averages are incomplete — request p95 or p99.

## Trigger

Load this skill when:
- The specification contains performance criteria (latency, throughput, memory, CPU)
- A change touches a known performance-sensitive path (database queries, network I/O, serialization)
- Before release/deployment of a feature with performance requirements
- `orchestration` selects the full chain and performance criteria exist

Do NOT load this skill for:
- Changes with no performance criteria in the spec
- Refactoring that provably preserves behavior (characterization tests verify this)
- Pure config changes with no runtime impact

## Process

### Step 1: Extract Criteria from Spec

Read the specification and extract every measurable performance criterion:

```
Perf criteria:
- [Metric name]: [threshold] at [percentile if applicable] under [conditions]
  Example: "API response time: <200ms at p95 for 1000 concurrent users"
  Example: "Memory: <256MB RSS under sustained load for 1 hour"

Criteria checklist:
- [ ] Each criterion has a specific threshold (not "fast enough")
- [ ] Each criterion has measurement conditions (load, concurrency, data size)
- [ ] Each criterion has a percentile or distribution requirement
```

Flag any criterion that is unmeasurable ("should be fast") or underspecified ("under heavy load").

### Step 2: Design the Benchmark

```
1. Benchmark scope: what code path does the criterion measure?
2. Measurement tool: how will you capture the metric?
   - Latency: application-level timing, load testing tool (k6, locust, wrk)
   - Memory: OS-level monitoring (/proc, ps, heaptrack)
   - Throughput: requests/second, items/second
3. Input data: what size, shape, and variety of inputs?
   - Empty, typical, large, edge-case inputs
4. Environment control:
   - Warm-up runs? (yes, unless cold-start is the criterion)
   - GC between runs? (yes, to isolate allocation from timing)
   - Competing load? (isolated environment for baseline, realistic load for stress)
```

### Step 3: Run with Statistical Control

```
1. Minimum trials: 5-10 (never 1 — single-point measurements are non-reproducible)
2. Warm-up: discard first N iterations (JIT warm-up, cache population)
3. Report: for each metric, report:
   - min, max, mean, median, p90, p95, p99
   - standard deviation
4. Check for outliers: if max > 10x p95, investigate (GC pause, I/O stall, network blip)
```

### Step 4: Compare to Criteria

```
Metric                   | Measured p95 | Threshold | Pass?
API latency (1000 conn)  | 187ms        | 200ms     | PASS
API latency (5000 conn)  | 340ms        | 200ms     | FAIL

For FAIL: is the criterion correct? Is the implementation correct? Is the test environment representative?
For PASS: is the margin sufficient? 187ms vs. 200ms is within noise — consider widening the margin or adding headroom.
```

### Step 5: Report with Evidence

```
Performance verification report:

Spec criteria:
- [criterion 1] → [result: PASS/FAIL with measured value]
- [criterion 2] → [result]

Methodology:
- Tool: [benchmark tool]
- Trials: [N trials, X warm-up iterations]
- Environment: [machine spec, competing load]

Recommendation:
- All criteria met → verify under production-like conditions if staging was used
- Criteria not met → flag as BLOCKER with identified bottleneck if known
- Marginal pass → WARNING: insufficient margin, consider optimization or relaxed criterion
```

## Evidence

After completing this skill:
- [ ] Performance criteria extracted from spec
- [ ] Benchmark designed and documented
- [ ] Multi-trial results with distribution statistics
- [ ] Each criterion compared to measurement (PASS/FAIL with values)
- [ ] Report with methodology and recommendation

## Exit Gate

Performance verification is complete when:
- Every spec criterion has been measured
- PASS/FAIL is determined for each
- Methodology is documented well enough to reproduce
- BLOCKERS (FAILs) have been reported with the measurement gap

## Handoff

After this skill:
- PASS: **`release-management`** (if shipping a versioned release) → **`integration-deployment`** — proceed to deploy
- FAIL: **`systematic-debugging`** — treat performance gap as a bug
- Marginal PASS: **`code-review`** — flag as WARNING

## Anti-Patterns

- **Single-sample verification**: Running the benchmark once and concluding "it's fine." Your single run could be the best run, the worst run, or the median — you don't know which.
- **Non-representative load**: Testing with 10 users when the spec says 1000. A O(n²) algorithm looks fine at n=10 and catastrophically fails at n=1000.
- **Mean-only reporting**: "Average latency is 50ms" — and p99 is 5,000ms because of GC pauses. Mean hides the tail. Always report distributions.
- **Testing in isolation**: "It's fast on my machine." Production has competing load, network latency, cold caches, and GC pressure. The test environment must match production or explicitly document the gap.
- **Optimization without measurement**: "This should be faster" without a benchmark. Before optimization: measure (current state). After optimization: measure again (new state). The difference IS the optimization.
- **Threshold anchoring**: "$200ms threshold, we got 199ms — ship it." Measurement noise could push this to 205ms in production. Leave headroom or improve the benchmark precision.
