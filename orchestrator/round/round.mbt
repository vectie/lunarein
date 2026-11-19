///|
pub(all) suberror RoundError {
  InvalidCapacity
  InvalidState(expected~ : RoundState, actual~ : RoundState)
  ForeignPolicy
  DuplicateRollout
  UnknownRollout
  DuplicateAdvantage
  EvidenceShapeMismatch
  EmptyRound
} derive(Debug, Eq)

///|
pub(all) enum RoundState {
  CollectingRollouts
  AwaitingAdvantages
  ReadyForTraining
  RoundAborted
} derive(Debug, Eq)

///|
pub(all) enum RoundAbortReason {
  RolloutFailure
  RewardFailure
  TrainerFailure
  PublicationFailure
  OperatorRequested
} derive(Debug, Eq)

///|
priv enum TrainingEvidence {
  PolicyGradient(@advantage.AdvantageEvidence)
  PolicyAndValue(@advantage.PpoTargetEvidence)
  CorrectedPolicyGradient(@correction.CorrectedAdvantageEvidence)
}

///|
pub struct RoundOwner {
  priv policy : @identity.PolicyGeneration
  priv rollout_lookup_keys : FixedArray[UInt64]
  priv rollout_lookup_values : FixedArray[Int32]
  priv trajectory_identities : FixedArray[
    @trajectory.TrajectoryEvidenceIdentity?,
  ]
  priv training_evidence : FixedArray[TrainingEvidence?]
  priv mut rollout_count : Int32
  priv mut advantage_count : Int32
  priv mut state : RoundState
  priv mut abort_reason : RoundAbortReason?
}

///|
pub fn RoundOwner::new(
  policy : @identity.PolicyGeneration,
  maximum_rollouts : Int32,
) -> Self raise RoundError {
  if maximum_rollouts <= 0 || maximum_rollouts > 1048576 {
    raise InvalidCapacity
  }
  let mut lookup_capacity = 2
  while lookup_capacity < maximum_rollouts * 2 {
    lookup_capacity *= 2
  }
  {
    policy,
    rollout_lookup_keys: FixedArray::make(lookup_capacity, 0UL),
    rollout_lookup_values: FixedArray::make(lookup_capacity, 0),
    trajectory_identities: FixedArray::make(maximum_rollouts, None),
    training_evidence: FixedArray::make(maximum_rollouts, None),
    rollout_count: 0,
    advantage_count: 0,
    state: CollectingRollouts,
    abort_reason: None,
  }
}

///|
fn RoundOwner::require_state(
  self : Self,
  expected : RoundState,
) -> Unit raise RoundError {
  if self.state != expected {
    raise InvalidState(expected~, actual=self.state)
  }
}

///|
fn RoundOwner::find_rollout(self : Self, rollout_id : UInt64) -> Int32 {
  let mixed = rollout_id ^ (rollout_id >> 33) ^ (rollout_id >> 17)
  let start = (mixed % self.rollout_lookup_keys.length().to_uint64()).to_int()
  for probe in 0..<self.rollout_lookup_keys.length() {
    let lookup_index = (start + probe) % self.rollout_lookup_keys.length()
    let key = self.rollout_lookup_keys[lookup_index]
    if key == rollout_id {
      return self.rollout_lookup_values[lookup_index] - 1
    }
    if key == 0UL {
      return -1
    }
  }
  -1
}

///|
fn RoundOwner::insert_rollout(
  self : Self,
  rollout_id : UInt64,
  item_index : Int32,
) -> Unit raise RoundError {
  let mixed = rollout_id ^ (rollout_id >> 33) ^ (rollout_id >> 17)
  let start = (mixed % self.rollout_lookup_keys.length().to_uint64()).to_int()
  for probe in 0..<self.rollout_lookup_keys.length() {
    let lookup_index = (start + probe) % self.rollout_lookup_keys.length()
    if self.rollout_lookup_keys[lookup_index] == 0UL {
      self.rollout_lookup_keys[lookup_index] = rollout_id
      self.rollout_lookup_values[lookup_index] = item_index + 1
      return
    }
  }
  raise InvalidCapacity
}

///|
pub fn RoundOwner::admit(
  self : Self,
  trajectory : @trajectory.Trajectory,
) -> Unit raise RoundError {
  self.require_state(CollectingRollouts)
  if trajectory.policy() != self.policy {
    raise ForeignPolicy
  }
  if self.rollout_count >= self.trajectory_identities.length() {
    raise InvalidCapacity
  }
  let rollout_id = trajectory.rollout_id().value()
  if self.find_rollout(rollout_id) >= 0 {
    raise DuplicateRollout
  }
  self.insert_rollout(rollout_id, self.rollout_count)
  self.trajectory_identities[self.rollout_count] = Some(
    trajectory.evidence_identity(),
  )
  self.rollout_count += 1
}

///|
pub fn RoundOwner::seal_rollouts(self : Self) -> Unit raise RoundError {
  self.require_state(CollectingRollouts)
  if self.rollout_count == 0 {
    raise EmptyRound
  }
  self.state = AwaitingAdvantages
}

///|
pub fn RoundOwner::accept_advantage(
  self : Self,
  evidence : @advantage.AdvantageEvidence,
) -> Unit raise RoundError {
  self.require_state(AwaitingAdvantages)
  if evidence.policy() != self.policy {
    raise ForeignPolicy
  }
  let index = self.find_rollout(evidence.rollout_id().value())
  if index < 0 {
    raise UnknownRollout
  }
  guard self.trajectory_identities[index] is Some(trajectory_identity) else {
    raise UnknownRollout
  }
  if !evidence.trajectory_identity().same(trajectory_identity) {
    raise EvidenceShapeMismatch
  }
  if self.training_evidence[index] is Some(_) {
    raise DuplicateAdvantage
  }
  self.training_evidence[index] = Some(PolicyGradient(evidence))
  self.advantage_count += 1
  if self.advantage_count == self.rollout_count {
    self.state = ReadyForTraining
  }
}

///|
pub fn RoundOwner::accept_ppo_target(
  self : Self,
  evidence : @advantage.PpoTargetEvidence,
) -> Unit raise RoundError {
  self.require_state(AwaitingAdvantages)
  if evidence.policy() != self.policy {
    raise ForeignPolicy
  }
  let index = self.find_rollout(evidence.rollout_id().value())
  if index < 0 {
    raise UnknownRollout
  }
  guard self.trajectory_identities[index] is Some(trajectory_identity) else {
    raise UnknownRollout
  }
  if !evidence.trajectory_identity().same(trajectory_identity) {
    raise EvidenceShapeMismatch
  }
  if self.training_evidence[index] is Some(_) {
    raise DuplicateAdvantage
  }
  self.training_evidence[index] = Some(PolicyAndValue(evidence))
  self.advantage_count += 1
  if self.advantage_count == self.rollout_count {
    self.state = ReadyForTraining
  }
}

///|
pub fn RoundOwner::accept_corrected_advantage(
  self : Self,
  evidence : @correction.CorrectedAdvantageEvidence,
) -> Unit raise RoundError {
  self.require_state(AwaitingAdvantages)
  if evidence.source_policy() != self.policy {
    raise ForeignPolicy
  }
  let index = self.find_rollout(evidence.rollout_id().value())
  if index < 0 {
    raise UnknownRollout
  }
  guard self.trajectory_identities[index] is Some(trajectory_identity) else {
    raise UnknownRollout
  }
  if !evidence.trajectory_identity().same(trajectory_identity) {
    raise EvidenceShapeMismatch
  }
  if self.training_evidence[index] is Some(_) {
    raise DuplicateAdvantage
  }
  self.training_evidence[index] = Some(CorrectedPolicyGradient(evidence))
  self.advantage_count += 1
  if self.advantage_count == self.rollout_count {
    self.state = ReadyForTraining
  }
}

///|
pub fn RoundOwner::abort(
  self : Self,
  reason : RoundAbortReason,
) -> Unit raise RoundError {
  match self.state {
    CollectingRollouts | AwaitingAdvantages | ReadyForTraining => {
      self.abort_reason = Some(reason)
      self.state = RoundAborted
    }
    RoundAborted =>
      raise InvalidState(expected=CollectingRollouts, actual=RoundAborted)
  }
}

///|
pub fn RoundOwner::policy(self : Self) -> @identity.PolicyGeneration {
  self.policy
}

///|
pub fn RoundOwner::contains_rollout(
  self : Self,
  rollout_id : @identity.RolloutId,
) -> Bool {
  self.find_rollout(rollout_id.value()) >= 0
}

///|
pub fn RoundOwner::training_evidence_matches(
  self : Self,
  item : @update.TrainingItemRef,
) -> Bool {
  let index = self.find_rollout(item.rollout_id().value())
  if index < 0 {
    return false
  }
  match self.training_evidence[index] {
    Some(PolicyGradient(evidence)) => evidence.matches_training_item(item)
    Some(PolicyAndValue(evidence)) => evidence.matches_training_item(item)
    Some(CorrectedPolicyGradient(evidence)) =>
      evidence.matches_training_item(item)
    None => false
  }
}

///|
pub fn RoundOwner::state(self : Self) -> RoundState {
  self.state
}

///|
pub fn RoundOwner::rollout_count(self : Self) -> Int32 {
  self.rollout_count
}

///|
pub fn RoundOwner::advantage_count(self : Self) -> Int32 {
  self.advantage_count
}

///|
pub fn RoundOwner::abort_reason(self : Self) -> RoundAbortReason? {
  self.abort_reason
}
