# SLIME reference notes

LunaRein uses `../slm` as a behavioral reference, not a dependency or source
template.

The comparison was made against `train.py`, `train_async.py`,
`slime/ray/rollout.py`, `slime/ray/actor_group.py`, and the rollout-buffer
plugin. In particular, LunaRein preserves the visible generate/train/weight
handoff and token-aligned training data, while replacing Ray object ownership,
runtime-loaded rollout functions, mutable loss masks, and implicit weight
versions with typed contracts.

## Semantics retained

- one visible rollout -> buffer -> train -> weight-update dataflow;
- token-aligned rollout logprobs and loss eligibility;
- rollout groups for GRPO-style normalization;
- frozen reference/reward runtimes;
- explicit weight versions;
- rollout-only and train-only replay/debugging;
- full and eventually delta weight synchronization;
- deterministic train/rollout alignment gates;
- synchronous dataflow and explicitly bounded stale-evidence correction.

## Debt deliberately rejected

- a global argument namespace passed into unrelated components;
- a mutable sample aggregate containing payload, rewards, masks, backend
  metadata, routing details, speculative metrics, and training state;
- dynamically loaded Python functions and compatibility return shapes;
- direct Ray, SGLang, Megatron, and torch types in orchestration code;
- duplicated synchronous and asynchronous entry loops;
- backend argument pass-through as a public extension mechanism;
- implicit dictionaries whose valid keys depend on the selected algorithm.

## Design translation

SLIME concept | LunaRein owner
--- | ---
`Sample` | separate trajectory, score, advantage, and update contracts
Data Buffer | bounded multi-group update-cycle owner
SGLang rollout | versioned rollout/scoring protocol, initially served by LunaFlux
Megatron actor | versioned trainer protocol with one selected adapter
Ray placement | LunaNexa or operator-owned deployment
custom import hook | typed external environment/reward protocol
sync/async scripts | synchronous v1 state machine; async deferred behind gates
