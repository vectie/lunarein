# LunaRein technical-debt policy

## Structural budgets

- Prefer cohesive files below 500 lines.
- Files above 800 lines require an architecture decision and split plan.
- A package owns one stable responsibility and its public concrete types.
- No global configuration or global mutable runtime context.
- No catch-all sample, batch, trainer, backend, or experiment object.
- No `Any`, untyped metadata map, or string-key option map in core contracts.

## Extension policy

- No runtime-loaded source hooks or import-path plugins.
- New algorithms add typed evidence or a focused strategy package.
- New backends add adapters behind an existing protocol or propose a protocol
  change; backend flags never pass through the core.
- Compatibility shims have an owner, removal condition, and deadline.

## Correctness

- Every rollout token is aligned with origin, trainability, and logprob evidence.
- Every derived score names the exact rollout and policy generation.
- Every update names the exact parent policy.
- Missing, duplicate, stale, nonfinite, or misaligned evidence fails closed.
- Replay tests cover ordering and identity substitution.

## Concurrency

- Synchronous and bounded stale-replay operation share one state machine.
- V1 owns one pending optimizer/publication generation; speculative overlap is
  prohibited until recoverable publication and aggregate memory gates exist.
- Cancellation cannot relabel partial evidence as complete.
- Retry never invents a new rollout or policy identity.

## Runtime boundaries

- Core packages perform no network, filesystem, process, or accelerator work.
- External resources have explicit owners and deterministic close paths.
- Steady-state orchestration uses bounded storage; growth requires an explicit
  capacity decision and benchmark.
- Production code performs no runtime compilation or arbitrary code loading.

## Review checklist

1. Which package owns the new state and public types?
2. Does the evidence retain exact policy and rollout lineage?
3. Is a generic metadata/configuration escape hatch being introduced?
4. Can unsupported behavior fail before mutation or resource acquisition?
5. Does concurrent or replay behavior reuse the canonical state machine?
6. Is backend vocabulary confined to its adapter?
7. What replay, substitution, and exhaustion tests prove the transition?
8. What removes any temporary compatibility code?
