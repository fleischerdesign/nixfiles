# 0003 - Reconciliation engine: Crossplane

- **Status:** accepted
- **Date:** 2026-10-03

## Context

The fleet must reconcile several domains - identity, workloads, tenant data, DNS - whose only shared
requirement is: map desired objects to concrete resources, and external systems to objects, without
writing a bespoke controller for each. A per-use-case reconciler is unmaintainable by construction.

## Decision

Use **Crossplane** as the generic reconciliation engine, extended by **providers** (external APIs) and
**compositions** (object-to-object mappings). Domain logic is expressed as data - an XRD for the
schema, a composition for the mapping - not as code.

## Consequences

- One engine serves every domain; the cost of a new domain is a schema and a composition, not a program.
- External systems are covered by reusable providers; where a first-party provider is missing, the
  Terraform provider is wrapped via `provider-terraform` rather than reimplemented.
- The engine and its providers are additional, higher-order infrastructure: they must be pinned
  (Nix does), backed up (**D5**) and threat-modelled (**R12**).
- Composition logic can grow complex; that complexity is declarative and reviewable, which is the
  property the alternative lacks.

## Alternatives

- **controller-runtime / Kubebuilder per domain** - the direct expression of "one reconciler per use
  case"; rejected.
- **Flux + tofu-controller only** - excellent for external systems with Terraform providers, but no
  composition abstraction, so internal resource graphs (a `Gateway` to five objects) would be authored
  by hand. Retained as the fallback for a provider gap, not the primary engine.
- **Cloud-native Go operator** - the most flexible and the most expensive to maintain; rejected at this
  scale.
