# LunaRein implementation guide

LunaRein is a documentation-first MoonBit-native control plane for language-
model reinforcement learning. Before implementation, read `README.mbt.md`,
`docs/PRODUCT_CONTRACT.md`, `docs/ARCHITECTURE.md`, `docs/PLAN.md`, and
`docs/DEBT_POLICY.md`.

## Product boundary

LunaRein owns policy-generation lineage, rollout-group coordination, immutable
trajectory evidence, scoring joins, advantage construction, update scheduling,
checkpoint-publication coordination, and bounded stale replay.

LunaFlux remains an opaque rollout and scoring runtime. LunaNexa remains the
fleet and deployment controller. LunaRein must not import either repository.

## Language and runtime

- Write first-party control-path code in MoonBit targeting native builds.
- Do not add Python, Ray, PyTorch, Megatron, or SGLang to the production control
  plane.
- Backend adapters use narrow versioned protocols and typed capabilities.
- Every trajectory and score remains bound to an exact policy generation.
- Native and accelerator resources require explicit deterministic release.

## Debt controls

- No global argument/configuration object.
- No catch-all sample record, metadata map, or `Any`-shaped extension surface.
- No runtime-loaded source hook or import-path plugin.
- V1 permits one pending optimizer/publication generation. Future concurrency
  must reuse the same state machine and first add in-flight recovery and
  aggregate resource gates.
- Backend-specific vocabulary stays in backend adapter packages.
- Public concrete types belong to the public package that owns them.
- Prefer files below 500 lines. Files above 800 lines require an architecture
  decision and split plan.

## Validation

At a completed phase boundary run:

~~~sh
moon info
moon fmt
moon check --target native --deny-warn --warn-list +73
moon test --target native --deny-warn --warn-list +73
scripts/validate-boundaries.sh
~~~
