# Baseline

> The Phase-0 measurements. A plan that does not state its starting point cannot prove a phase
> succeeded: the repository's third non-negotiable is that the expectation is written next to the
> measurement. Every row below is a command, an expectation, and the decision it closes.

## 1. Why a baseline

The roadmap's exit criteria are relative - "static behaviour is unchanged", "the control plane is
mesh-only", "the fleet clears the threshold". Relative claims need an absolute reference. This document
is that reference, taken once, before the control plane exists, and re-taken after each phase.

## 2. Known inventory facts

These are declared, not measured, and are cited rather than restated:
[`../architecture.md`](../architecture.md) §2 (hosts), [`../naming.md`](../naming.md) (names),
[`../../inventory/identity.nix`](../../inventory/identity.nix) (`ai-users` and its members).

## 3. Measurements

| Id | Host class | Command | Expectation | Closes |
|---|---|---|---|---|
| B1 | all | `ls -l /dev/kvm` | present only where a VM actuator is feasible | D1 |
| B2 | all | `systemd-detect-virt` | the substrate is identified; nested virt is proven, not assumed | D1 |
| B3 | all | `lscpu \| grep -Eo 'vmx\|svm'` | matches B1 | D1 |
| B4 | all | `stat -fc %T /sys/fs/cgroup` | `cgroup2fs` (unified hierarchy) | D11 |
| B5 | all | `ss -lntupH` | every listener is a declared endpoint | R8, R12 |
| B6 | all | `nft list tables` | no table the fleet cannot name | R1 |
| B7 | all | `nft list ruleset \| wc -l`, repeat after k3s start | k3s adds its own tables and flushes none of ours | R1 |
| B8 | all | `ss -lntupH` after k3s start, diff against B5 | no NodePort listener appears (service-LB disabled) | R12 |
| B9 | all | `resolvectl` / a query against the local resolver while k3s runs | CoreDNS does not answer the host's own names | D2 |
| B10 | all | `systemctl show -p MemoryCurrent k3s`, `du -sh /var/lib/rancher/k3s` | the control plane's footprint, to size the host | D1 |
| B11 | all | churn log: identity changes over 30 days, and the number of distinct actors | the fleet is above the threshold or is not (**D8**) | D8, R7 |
| B12 | servers | count of `ai-users` members and their services | the size of the first workload domain | S2 |
| B13 | all | `sops -d ... \| yq 'keys'` (keys only, never values) | the platform secret inventory | D10 |
| B14 | all | `systemd-analyze` boot time, before and after | static independence is a measured, not assumed, property | R8 |
| B15 | all | wall-clock of `nix flake check` and a `nod switch` | the batch loop's real latency, the number the plan replaces | problem.md §1 |

## 4. The churn threshold

**D8** needs a number, not a feeling. The proposal:

> A domain crosses the line when it changes **more than once a month** *and* is changed by **more than
> one actor** (human through a UI, an external system, or an event). Either condition alone does not
> qualify a domain for continuous reconciliation.

B11 measures the first; the second is observed from the systems that mutate the domain. A domain that
fails either test stays Nix (**R7**), and this document records the measurement that says so.

## 5. Record format

Each measurement is recorded as: command, raw output, the expectation from the table, and the verdict -
pass, fail, or *inconclusive*, which is a fail that has not yet been understood. A baseline with an
inconclusive row does not authorise the phase that depends on it.
