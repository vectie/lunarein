# LunaRein implementation plan

## Status

- Phase 0 core contracts: implemented; generated interfaces are refreshed at
  each release gate.
- Phase 1 protocol contracts: implemented; independent physical numerical
  conformance against a LunaFlux adapter remains an integration gate.
- Phase 2 deterministic CPU algorithms: implemented.
- Phase 3 trainer protocol: implemented; no trainer adapter is release-qualified
  yet.
- Phase 4 publication state model and native filesystem adapter: implemented;
  cross-process transport qualification remains open.
- Phase 5 synchronous multi-group updates and bounded stale replay: implemented.
  Concurrent generations and in-flight crash recovery are deferred and must not
  be advertised as v1 behavior.
- Phase 6 operations: not implemented. Commands, authoritative accounting,
  recovery, campaigns, and LunaNexa integration remain release gates.

## Phase 0 — Contracts and repository boundary

Outcome: a native MoonBit module with exact identity, trajectory, score, and
round-transition contracts.

Gate:

- warning-denied native check and tests pass;
- generated interfaces contain only intended public types;
- core imports no LunaFlux, LunaNexa, Python, Ray, PyTorch, Megatron, or SGLang;
- duplicate, stale, misaligned, and nonfinite evidence fails closed.

## Phase 1 — Rollout and scoring protocol

Define one bounded versioned protocol for:

- N rollouts per prompt group;
- exact actor generation and tokenizer identity;
- deterministic sampling identity;
- token origin, model logprob, and sampling logprob;
- partial/cancelled terminal evidence;
- teacher-forced policy and reference scoring.

LunaFlux implements the runtime side without either repository importing the
other. Physical gates compare token IDs and both logprob meanings against an
independent referee.

## Phase 2 — Reward and advantage construction

- typed scalar and token reward providers;
- verifiable reward evidence;
- GRPO group normalization;
- REINFORCE and GAE/PPO returns;
- explicit KL and reference-score joins;
- loss masks derived from token origin, never caller-supplied parallel arrays;
- deterministic CPU reference tests.

## Phase 3 — Trainer protocol

Define one trainer protocol carrying immutable batches and returning optimizer-
step evidence plus a content-addressed candidate policy. Select one trainer
backend explicitly. Do not support generic backend argument pass-through.

## Phase 4 — Weight publication

- full safetensors publication first;
- atomic no-overwrite candidate directories;
- exact parent/target generation and tensor vocabulary;
- bounded chunked transfer;
- acknowledgements from every rollout rank;
- delta transport only after full publication is correct and measured;
- no in-place mutation of the last known-good artifact.

## Phase 5 — Bounded stale replay and future pipelining

- one pending generation in v1;
- multiple prompt groups per canonical update cycle;
- explicit maximum staleness;
- importance-correction evidence when required;
- backpressure and cancellation;
- quiescent checkpointing in v1;
- no alternate asynchronous training loop.

Future concurrent-generation work must add in-flight crash/replay recovery,
aggregate memory budgets, and physical publication recovery before increasing
`PendingUpdateCapacity` above one.

## Phase 6 — Operations and LunaNexa integration (open)

- digest-pinned experiment plan;
- health, readiness, drain, metrics, and replay commands;
- LunaNexa adapter owned only by LunaNexa;
- reproducible long-running physical campaigns;
- published throughput, convergence, and failure evidence.
