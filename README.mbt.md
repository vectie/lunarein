# LunaRein

**LunaRein** is a MoonBit-native control plane for language-model reinforcement
learning. The name is exactly `Luna` + `Rein`.

LunaRein takes the useful dataflow demonstrated by SLIME—rollout generation,
behavior logprobs, rewards, advantages, training updates, and policy weight
synchronization—and rebuilds it around explicit ownership and versioned
contracts.

~~~text
environment / prompt source
          |
          v
rollout runtime ----> immutable trajectories ----> reward and score providers
   (LunaFlux)                 |                            |
                              +------------+---------------+
                                           v
                                  advantage construction
                                           |
                                           v
                                      trainer runtime
                                           |
                                           v
                                next policy generation
~~~

## Product boundary

LunaRein owns:

- exact policy-generation lineage;
- rollout groups and immutable token-aligned trajectory evidence;
- distinct model and sampling logprob semantics;
- reward, reference-score, and advantage joins;
- deterministic round/update state;
- checkpoint-publication protocol ownership;
- typed protocols for rollout, scoring, reward, and trainer runtimes.

LunaRein does not own:

- model serving, KV memory, token scheduling, or kernels (LunaFlux);
- fleet placement, node lifecycle, or tenant policy (LunaNexa);
- a general agent framework, sandbox platform, or application runtime;
- arbitrary Python hooks, backend argument pass-through, or runtime code loading.

## Implemented v1 core

The native control-plane library now contains:

- `contracts/identity`, `trajectory`, `reward`, `experiment`, and `update` for
  exact lineage and immutable evidence;
- `protocols/rollout` for bounded N-slot generation and teacher-forced scoring;
- `algorithms/advantage` for REINFORCE, reference-KL, GRPO, and GAE/PPO targets;
- `protocols/trainer` and `protocols/publication` for optimizer-step evidence
  and a fail-closed publication state model;
- `adapters/publication_fs` for byte-verifying, atomic, no-overwrite
  safetensors publication with exact-digest restart recovery;
- `orchestrator/round` and `orchestrator/cycle` for one generation-bound
  multi-group rollout-to-committed-policy state machine;
- `orchestrator/pipeline` for serialized committed lineage, backpressure, and
  pipeline-owned bounded stale replay with typed importance correction.

The end-to-end tests execute the complete in-memory protocol flow. LunaFlux and
a selected trainer can implement those protocols without a source dependency on
LunaRein.

The repository does not yet claim full physical production readiness. A
qualified LunaFlux numerical adapter, one selected trainer adapter, transport
qualification, in-flight orchestration recovery, operational commands, and
long-running physical campaigns remain explicit release gates in the plan.

## Validation

~~~sh
moon info
moon fmt
moon check --target native --deny-warn --warn-list +73
moon test --target native --deny-warn --warn-list +73
scripts/validate-boundaries.sh
~~~

See [the product contract](docs/PRODUCT_CONTRACT.md),
[architecture](docs/ARCHITECTURE.md), [implementation plan](docs/PLAN.md),
[debt policy](docs/DEBT_POLICY.md), and
[SLIME reference notes](docs/SLIME_REFERENCE.md).
