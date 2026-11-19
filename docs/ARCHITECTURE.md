# LunaRein architecture

## Dependency direction

~~~text
contracts/identity
  ├─ contracts/trajectory ── contracts/reward ── algorithms/advantage
  ├─ contracts/experiment
  └─ contracts/update

protocols/{rollout,trainer,publication}
                 │
                 v
orchestrator/round ── orchestrator/cycle ── orchestrator/pipeline
                 │
adapters/* ---> external runtimes
~~~

Core contracts import no backend, network, filesystem, training, serving, or
fleet package. Adapters translate external protocols into the types owned by
the corresponding public contract package.

## Round ownership

One round owner is bound to one actor policy generation. It admits immutable
trajectories, seals the rollout set, and accepts one advantage evidence value
for every admitted rollout. An update-cycle owner then validates a canonical
training batch, exact trainer result, and committed publication.

~~~text
CollectingRollouts
  -> AwaitingAdvantages
  -> ReadyForTraining

GatheringRollouts -> ... -> TrainerDispatched -> CandidateAccepted
  -> PolicyCommitted -> CycleCompleted
~~~

Invalid ordering, duplicate rollouts/scores, foreign generations, and broken
policy lineage are rejected before mutation.

One update cycle may own up to sixteen prompt groups and 65,536 rollout slots.
The v1 coordinator serializes optimizer/publication generations and permits
bounded stale replay only through an exact source-to-target lineage witness and
typed importance correction. Speculative generation overlap is not a v1 claim.

## Data design

Trajectory, reward, reference scoring, advantages, training references, and
update evidence remain separate. This prevents one shared mutable `Sample` object from accumulating
backend metadata, observability state, task payloads, and training tensors.

Model logprob and sampling logprob are distinct:

- model logprob is the normalized actor-model probability used by the loss;
- sampling logprob is the probability under the actual temperature/filtering
  distribution that generated the token.

Neither can silently stand in for the other.

## Runtime topology

LunaRein is a caller of opaque runtimes:

- rollout/scoring runtime: initially LunaFlux;
- reward/environment runtime: task-owned;
- trainer runtime: one explicitly selected implementation;
- deployment runtime: LunaNexa or an operator.

The core never imports LunaFlux, LunaNexa, Ray, PyTorch, Megatron, or SGLang.
Transport, credentials, resource placement, and process lifecycle stay outside
the deterministic round state machine.

## Failure model

- Rollout failure terminates or retries one rollout under explicit policy.
- Score failure leaves the round incomplete; it cannot publish an update.
- Trainer failure publishes no policy generation.
- A stale or substituted weight artifact cannot become a successor.
- `adapters/publication_fs` owns partial-publication cleanup and retry. It
  verifies chunk and full-artifact SHA-256, validates safetensors structure,
  and atomically installs a no-overwrite candidate directory before exposing
  committed protocol evidence. Cross-process transport remains a release gate.
- Raw prompts, responses, rewards, and token IDs are excluded from default logs.
