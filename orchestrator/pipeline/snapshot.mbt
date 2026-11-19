///|
pub(all) enum RetirementOutcome {
  Committed(@identity.PolicyGeneration)
  Aborted(@cycle.CycleAbortReason)
} derive(Debug, Eq)

///|
pub struct RetiredCycle {
  priv actor : @identity.PolicyGeneration
  priv outcome : RetirementOutcome
  priv rollout_count : Int32
  priv advantage_count : Int32
} derive(Debug, Eq)

///|
fn RetiredCycle::from_cycle(
  cycle : @cycle.UpdateCycle,
  outcome : RetirementOutcome,
) -> Self {
  {
    actor: cycle.training_policy(),
    outcome,
    rollout_count: cycle.rollout_count(),
    advantage_count: cycle.advantage_count(),
  }
}

///|
pub fn RetiredCycle::actor(self : Self) -> @identity.PolicyGeneration {
  self.actor
}

///|
pub fn RetiredCycle::outcome(self : Self) -> RetirementOutcome {
  self.outcome
}

///|
pub fn RetiredCycle::rollout_count(self : Self) -> Int32 {
  self.rollout_count
}

///|
pub fn RetiredCycle::advantage_count(self : Self) -> Int32 {
  self.advantage_count
}

///|
pub struct GenerationSnapshot {
  priv manifest : @experiment.ExperimentManifest
  priv state : @cycle.CycleState
  priv rollout_count : Int32
  priv advantage_count : Int32
  priv committed_policy : @identity.PolicyGeneration?
  priv abort_reason : @cycle.CycleAbortReason?
} derive(Debug, Eq)

///|
fn GenerationSnapshot::from_cycle(cycle : @cycle.UpdateCycle) -> Self {
  {
    manifest: cycle.manifest(),
    state: cycle.state(),
    rollout_count: cycle.rollout_count(),
    advantage_count: cycle.advantage_count(),
    committed_policy: cycle.committed_policy(),
    abort_reason: cycle.abort_reason(),
  }
}

///|
pub fn GenerationSnapshot::manifest(
  self : Self,
) -> @experiment.ExperimentManifest {
  self.manifest
}

///|
pub fn GenerationSnapshot::actor(self : Self) -> @identity.PolicyGeneration {
  self.manifest.actor()
}

///|
pub fn GenerationSnapshot::state(self : Self) -> @cycle.CycleState {
  self.state
}

///|
pub fn GenerationSnapshot::rollout_count(self : Self) -> Int32 {
  self.rollout_count
}

///|
pub fn GenerationSnapshot::advantage_count(self : Self) -> Int32 {
  self.advantage_count
}

///|
pub fn GenerationSnapshot::committed_policy(
  self : Self,
) -> @identity.PolicyGeneration? {
  self.committed_policy
}

///|
pub fn GenerationSnapshot::abort_reason(
  self : Self,
) -> @cycle.CycleAbortReason? {
  self.abort_reason
}

///|
/// An immutable ordered view of live cycle state. It is not restorable because
/// UpdateCycle does not expose the complete typed rollout, advantage, trainer,
/// and publication evidence needed to reconstruct an in-flight cycle.
pub struct PipelineSnapshot {
  priv manifest : @experiment.ExperimentManifest
  priv state : PipelineState
  priv retired_count : UInt64
  priv generations : ReadOnlyArray[GenerationSnapshot]
} derive(Debug, Eq)

///|
pub fn PipelineOwner::snapshot(
  self : Self,
) -> PipelineSnapshot raise PipelineError {
  let generations : Array[GenerationSnapshot] = []
  for offset in 0..<self.count {
    let index = self.slot_index(offset)
    guard self.slots[index] is Some(cycle) else { raise InvalidCycleSnapshot }
    generations.push(GenerationSnapshot::from_cycle(cycle))
  }
  {
    manifest: self.manifest,
    state: self.state,
    retired_count: self.retired_count,
    generations: ReadOnlyArray::from_array(generations),
  }
}

///|
pub fn PipelineSnapshot::manifest(
  self : Self,
) -> @experiment.ExperimentManifest {
  self.manifest
}

///|
pub fn PipelineSnapshot::state(self : Self) -> PipelineState {
  self.state
}

///|
pub fn PipelineSnapshot::retired_count(self : Self) -> UInt64 {
  self.retired_count
}

///|
pub fn PipelineSnapshot::in_flight_count(self : Self) -> Int32 {
  self.generations.length()
}

///|
pub fn PipelineSnapshot::generation_at(
  self : Self,
  index : Int32,
) -> GenerationSnapshot raise PipelineError {
  if index < 0 || index >= self.generations.length() {
    raise InvalidCycleSnapshot
  }
  self.generations[index]
}

///|
/// Exact restart state at a quiescent cycle boundary. The manifest remains the
/// authoritative experiment and capacity binding across persistence.
pub struct QuiescentCheckpoint {
  priv manifest : @experiment.ExperimentManifest
  priv staleness_policy : @staleness.StalenessPolicy
  priv last_opened : @identity.PolicyGeneration?
  priv required_next : @identity.PolicyGeneration?
  priv retired_count : UInt64
  priv state : PipelineState
} derive(Debug, Eq)

///|
fn manifest_with_actor(
  manifest : @experiment.ExperimentManifest,
  actor : @identity.PolicyGeneration,
) -> @experiment.ExperimentManifest {
  @experiment.ExperimentManifest::new(
    identity=manifest.identity(),
    actor~,
    dataset=manifest.dataset(),
    reward_policy=manifest.reward_policy(),
    tokenizer=manifest.tokenizer(),
    algorithm=manifest.algorithm(),
    limits=manifest.limits(),
  )
}

///|
fn validate_checkpoint(
  manifest : @experiment.ExperimentManifest,
  staleness_policy : @staleness.StalenessPolicy,
  last_opened : @identity.PolicyGeneration?,
  required_next : @identity.PolicyGeneration?,
  retired_count : UInt64,
  state : PipelineState,
) -> Unit raise PipelineError {
  if capacity_for(manifest, staleness_policy) <= 0 || state == Draining {
    raise InvalidCheckpoint
  }
  match last_opened {
    None =>
      if retired_count != 0UL || required_next is Some(_) {
        raise InvalidCheckpoint
      }
    Some(last) => {
      if retired_count == 0UL || last != manifest.actor() {
        raise InvalidCheckpoint
      }
      if state == Accepting && required_next is None {
        raise InvalidCheckpoint
      }
      match required_next {
        Some(required) => if !required.follows(last) { raise InvalidCheckpoint }
        None => ()
      }
    }
  }
}

///|
/// Reconstructs a typed checkpoint from persisted fields. Persistence-envelope
/// authentication remains an adapter responsibility.
pub fn QuiescentCheckpoint::new(
  manifest~ : @experiment.ExperimentManifest,
  staleness_policy~ : @staleness.StalenessPolicy,
  last_opened~ : @identity.PolicyGeneration?,
  required_next~ : @identity.PolicyGeneration?,
  retired_count~ : UInt64,
  state~ : PipelineState,
) -> Self raise PipelineError {
  validate_checkpoint(
    manifest, staleness_policy, last_opened, required_next, retired_count, state,
  )
  {
    manifest,
    staleness_policy,
    last_opened,
    required_next,
    retired_count,
    state,
  }
}

///|
pub fn PipelineOwner::checkpoint(
  self : Self,
) -> QuiescentCheckpoint raise PipelineError {
  if self.count != 0 {
    raise CheckpointRequiresQuiescence
  }
  let bound_manifest = match self.last_opened {
    Some(actor) => manifest_with_actor(self.manifest, actor)
    None => self.manifest
  }
  QuiescentCheckpoint::new(
    manifest=bound_manifest,
    staleness_policy=self.staleness_policy,
    last_opened=self.last_opened,
    required_next=self.required_next,
    retired_count=self.retired_count,
    state=self.state,
  )
}

///|
pub fn PipelineOwner::restore(
  checkpoint : QuiescentCheckpoint,
) -> Self raise PipelineError {
  validate_checkpoint(
    checkpoint.manifest,
    checkpoint.staleness_policy,
    checkpoint.last_opened,
    checkpoint.required_next,
    checkpoint.retired_count,
    checkpoint.state,
  )
  let owner = PipelineOwner::new(
    manifest=checkpoint.manifest,
    staleness_policy=checkpoint.staleness_policy,
  )
  owner.last_opened = checkpoint.last_opened
  owner.required_next = checkpoint.required_next
  owner.retired_count = checkpoint.retired_count
  owner.state = checkpoint.state
  owner
}

///|
pub fn QuiescentCheckpoint::manifest(
  self : Self,
) -> @experiment.ExperimentManifest {
  self.manifest
}

///|
pub fn QuiescentCheckpoint::staleness_policy(
  self : Self,
) -> @staleness.StalenessPolicy {
  self.staleness_policy
}

///|
pub fn QuiescentCheckpoint::last_opened_policy(
  self : Self,
) -> @identity.PolicyGeneration? {
  self.last_opened
}

///|
pub fn QuiescentCheckpoint::required_next_policy(
  self : Self,
) -> @identity.PolicyGeneration? {
  self.required_next
}

///|
pub fn QuiescentCheckpoint::retired_count(self : Self) -> UInt64 {
  self.retired_count
}

///|
pub fn QuiescentCheckpoint::state(self : Self) -> PipelineState {
  self.state
}
