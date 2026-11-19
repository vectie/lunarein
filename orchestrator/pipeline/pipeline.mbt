///|
pub(all) suberror PipelineError {
  InvalidCapacity
  InvalidState(expected~ : PipelineState, actual~ : PipelineState)
  Backpressure
  ManifestMismatch
  BrokenLineage
  UnknownGeneration
  NoInFlightGeneration
  RetirementCountExhausted
  OldestNotRetirable(actual~ : @cycle.CycleState)
  CommittedSuccessorMismatch
  InvalidCycleSnapshot
  CheckpointRequiresQuiescence
  InvalidCheckpoint
  Cycle(@cycle.CycleError)
  Staleness(@staleness.StalenessError)
} derive(Debug, Eq)

///|
pub(all) enum PipelineState {
  Accepting
  Draining
  Drained
} derive(Debug, Eq)

///|
/// The sole bounded owner of multiple canonical update cycles. Sync and async
/// callers drive these same transitions; the pipeline neither performs I/O nor
/// owns an alternate training loop.
pub struct PipelineOwner {
  priv manifest : @experiment.ExperimentManifest
  priv staleness_policy : @staleness.StalenessPolicy
  priv slots : FixedArray[@cycle.UpdateCycle?]
  priv mut head : Int32
  priv mut count : Int32
  priv mut last_opened : @identity.PolicyGeneration?
  priv mut required_next : @identity.PolicyGeneration?
  priv mut retired_count : UInt64
  priv mut state : PipelineState
}

///|
fn capacity_for(
  manifest : @experiment.ExperimentManifest,
  _staleness_policy : @staleness.StalenessPolicy,
) -> Int32 {
  manifest.limits().pending_updates().value().to_int()
}

///|
pub fn PipelineOwner::new(
  manifest~ : @experiment.ExperimentManifest,
  staleness_policy~ : @staleness.StalenessPolicy,
) -> Self raise PipelineError {
  let maximum_in_flight = capacity_for(manifest, staleness_policy)
  if maximum_in_flight <= 0 || maximum_in_flight > 1024 {
    raise InvalidCapacity
  }
  {
    manifest,
    staleness_policy,
    slots: FixedArray::make(maximum_in_flight, None),
    head: 0,
    count: 0,
    last_opened: None,
    required_next: None,
    retired_count: 0UL,
    state: Accepting,
  }
}

///|
fn compatible_manifest(
  expected : @experiment.ExperimentManifest,
  actual : @experiment.ExperimentManifest,
) -> Bool {
  expected.identity() == actual.identity() &&
  expected.dataset() == actual.dataset() &&
  expected.reward_policy() == actual.reward_policy() &&
  expected.tokenizer() == actual.tokenizer() &&
  expected.algorithm() == actual.algorithm() &&
  expected.limits() == actual.limits()
}

///|
fn PipelineOwner::slot_index(self : Self, offset : Int32) -> Int32 {
  (self.head + offset) % self.slots.length()
}

///|
fn PipelineOwner::find_actor(
  self : Self,
  actor : @identity.PolicyGeneration,
) -> Int32 {
  for offset in 0..<self.count {
    let index = self.slot_index(offset)
    match self.slots[index] {
      Some(cycle) => if cycle.training_policy() == actor { return index }
      None => ()
    }
  }
  -1
}

///|
fn PipelineOwner::require_openable(
  self : Self,
  manifest : @experiment.ExperimentManifest,
) -> Unit raise PipelineError {
  if self.state != Accepting {
    raise InvalidState(expected=Accepting, actual=self.state)
  }
  if self.count >= self.slots.length() {
    raise Backpressure
  }
  if !compatible_manifest(self.manifest, manifest) {
    raise ManifestMismatch
  }
  let actor = manifest.actor()
  match self.last_opened {
    None => if manifest != self.manifest { raise ManifestMismatch }
    Some(previous) =>
      match self.required_next {
        Some(required) =>
          if actor != required {
            raise CommittedSuccessorMismatch
          }
        None => if !actor.follows(previous) { raise BrokenLineage }
      }
  }
}

///|
fn PipelineOwner::insert_cycle(
  self : Self,
  actor : @identity.PolicyGeneration,
  cycle : @cycle.UpdateCycle,
) -> Unit {
  let tail = self.slot_index(self.count)
  self.slots[tail] = Some(cycle)
  self.count += 1
  self.last_opened = Some(actor)
  self.required_next = None
}

///|
pub fn PipelineOwner::open_cycle(
  self : Self,
  manifest : @experiment.ExperimentManifest,
  request : @rollout.RolloutGroupRequest,
) -> @cycle.UpdateCycle raise PipelineError {
  self.require_openable(manifest)
  let actor = manifest.actor()
  let cycle = @cycle.UpdateCycle::new(manifest, request) catch {
    error => raise Cycle(error)
  }
  self.insert_cycle(actor, cycle)
  cycle
}

///|
/// Opens an off-policy replay cycle only after this owner evaluates the exact
/// source-to-target lineage against its configured staleness bound.
pub fn PipelineOwner::open_stale_cycle(
  self : Self,
  manifest : @experiment.ExperimentManifest,
  request : @rollout.RolloutGroupRequest,
  lineage : ArrayView[@identity.PolicyGeneration],
) -> @cycle.UpdateCycle raise PipelineError {
  self.require_openable(manifest)
  let actor = manifest.actor()
  let staleness = self.staleness_policy.evaluate(
    source=request.actor(),
    target=actor,
    lineage~,
  ) catch {
    error => raise Staleness(error)
  }
  let cycle = @cycle.UpdateCycle::new_stale(manifest, request, staleness) catch {
    error => raise Cycle(error)
  }
  self.insert_cycle(actor, cycle)
  cycle
}

///|
pub fn PipelineOwner::cycle(
  self : Self,
  actor : @identity.PolicyGeneration,
) -> @cycle.UpdateCycle? {
  let index = self.find_actor(actor)
  if index < 0 {
    None
  } else {
    self.slots[index]
  }
}

///|
pub fn PipelineOwner::cancel_generation(
  self : Self,
  actor : @identity.PolicyGeneration,
  reason : @cycle.CycleAbortReason,
) -> Unit raise PipelineError {
  let index = self.find_actor(actor)
  if index < 0 {
    raise UnknownGeneration
  }
  guard self.slots[index] is Some(cycle) else { raise InvalidCycleSnapshot }
  cycle.abort(reason) catch {
    error => raise Cycle(error)
  }
}

///|
pub fn PipelineOwner::begin_drain(self : Self) -> Unit raise PipelineError {
  if self.state != Accepting {
    raise InvalidState(expected=Accepting, actual=self.state)
  }
  if self.count == 0 {
    self.state = Drained
  } else {
    self.state = Draining
  }
}

///|
pub fn PipelineOwner::retire_oldest(
  self : Self,
) -> RetiredCycle raise PipelineError {
  if self.count == 0 {
    raise NoInFlightGeneration
  }
  if self.retired_count == 0xffffffffffffffffUL {
    raise RetirementCountExhausted
  }
  guard self.slots[self.head] is Some(cycle) else { raise InvalidCycleSnapshot }
  let outcome = match cycle.state() {
    CycleCompleted => {
      guard cycle.committed_policy() is Some(successor) &&
        successor.follows(cycle.training_policy()) else {
        raise InvalidCycleSnapshot
      }
      Committed(successor)
    }
    CycleAborted => {
      guard cycle.abort_reason() is Some(reason) else {
        raise InvalidCycleSnapshot
      }
      Aborted(reason)
    }
    actual => raise OldestNotRetirable(actual~)
  }
  let retired = RetiredCycle::from_cycle(cycle, outcome)
  self.slots[self.head] = None
  self.head = (self.head + 1) % self.slots.length()
  self.count -= 1
  self.retired_count += 1UL
  match outcome {
    Committed(successor) =>
      if self.count == 0 {
        self.required_next = Some(successor)
      }
    Aborted(_) =>
      if self.count == 0 {
        self.required_next = None
        self.state = Drained
      }
  }
  if self.state == Draining && self.count == 0 {
    self.state = Drained
  }
  retired
}

///|
pub fn PipelineOwner::state(self : Self) -> PipelineState {
  self.state
}

///|
pub fn PipelineOwner::maximum_in_flight(self : Self) -> Int32 {
  self.slots.length()
}

///|
pub fn PipelineOwner::in_flight_count(self : Self) -> Int32 {
  self.count
}

///|
pub fn PipelineOwner::retired_count(self : Self) -> UInt64 {
  self.retired_count
}

///|
pub fn PipelineOwner::manifest(self : Self) -> @experiment.ExperimentManifest {
  self.manifest
}

///|
pub fn PipelineOwner::last_opened_policy(
  self : Self,
) -> @identity.PolicyGeneration? {
  self.last_opened
}

///|
pub fn PipelineOwner::required_next_policy(
  self : Self,
) -> @identity.PolicyGeneration? {
  self.required_next
}

///|
pub fn PipelineOwner::staleness_policy(
  self : Self,
) -> @staleness.StalenessPolicy {
  self.staleness_policy
}
