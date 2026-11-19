# LunaRein product contract

## Purpose

LunaRein coordinates bounded, reproducible language-model post-training loops.
It turns exact policy generations, prompts, rollout evidence, scores, and
trainer results into an authenticated next policy generation.

It is an RL control plane, not an inference engine, fleet controller, agent
runtime, or universal tensor framework.

## Owned responsibilities

LunaRein owns:

- policy, tokenizer, dataset, reward-policy, and experiment identities;
- rollout-group formation and oversampling/cancellation policy;
- immutable token-aligned trajectory evidence;
- explicit behavior-model and sampling-distribution logprobs;
- reward, reference score, value, mask, and advantage joins;
- synchronous update policy and bounded stale-replay correction;
- trainer requests, optimizer-step evidence, and checkpoint publication;
- native byte-verified, atomic, no-overwrite safetensors publication;

## External responsibilities

- LunaFlux owns rollout/scoring execution, tokenization, batching, KV, kernels,
  and device resources.
- A trainer runtime owns tensor execution, autograd, optimizer state, and
  accelerator collectives until a MoonBit-native trainer phase replaces it.
- LunaNexa owns machine placement, deployment, restart, routing, and artifact
  distribution.
- Environment runtimes own tools, sandboxes, simulators, and task semantics.

Every external runtime is addressed through a narrow versioned protocol and an
immutable identity. No external implementation type crosses into core packages.

## Canonical trajectory

A trajectory binds:

- rollout and group identity;
- exact actor policy generation;
- immutable prompt tokens;
- ordered response tokens;
- token origin (model or environment);
- model logprob and actual sampling logprob for every model-generated token;
- terminal disposition.

Rewards, reference scores, values, and advantages are separate evidence types.
They do not mutate or extend the trajectory.

## Policy lineage

Every noninitial policy generation names the exact actor digest of its parent.
A round may publish only the immediate successor of the generation that
produced its rollouts. Bounded-staleness policies may admit older evidence only
through a separate explicit correction contract; they never rewrite lineage.

## Compatibility

Rollout/scoring, trainer, and publication contracts share an exact v1 protocol
version. A transport adapter must still define and qualify its wire codec;
unknown-field policy and cross-process compatibility remain release gates.
Unsupported versions or algorithms, stale policy generations, missing
logprobs, partial score joins, and ambiguous weight updates fail closed.

## Explicit non-goals for v1

- Arbitrary Python callbacks or import-path plugins.
- Backend flag pass-through.
- A universal model or optimizer abstraction.
- In-process fleet scheduling or environment hosting.
- Silent train/rollout tokenizer or numerical mismatch.
- Unbounded asynchronous replay.
- Speculative concurrent optimizer generations in v1.
