///|
pub(all) suberror CycleError {
  InvalidState(expected~ : CycleState, actual~ : CycleState)
  IneligibleRollout
  DuplicateRolloutResponse
  IncompleteRolloutSet
  InsufficientUsableRollouts
  TokenizerMismatch
  RequestMismatch
  ExperimentLimitExceeded
  ForeignPolicy
  RewardPolicyMismatch
  AlgorithmMismatch
  CorrectionRequired
  CorrectionMismatch
  DuplicateGroup
  DuplicateGroupRollout
  TrainerLimitExceeded
  BatchCoverageMismatch
  TrainingShapeMismatch
  PublicationNotCommitted
  PublicationMismatch
  Round(@round.RoundError)
  Trainer(@trainer.TrainerProtocolError)
} derive(Debug, Eq)

///|
pub(all) enum CycleState {
  GatheringRollouts
  AwaitingAdvantages
  ReadyForTraining
  TrainerPrepared
  TrainerDispatched
  CandidateAccepted
  PolicyCommitted
  CycleCompleted
  CycleAborted
} derive(Debug, Eq)

///|
pub(all) enum CycleAbortReason {
  RolloutFailure
  RewardFailure
  TrainerFailure
  PublicationFailure
  OperatorRequested
} derive(Debug, Eq)

///|
pub struct UpdateCycle {
  priv manifest : @experiment.ExperimentManifest
  priv round : @round.RoundOwner
  priv training_policy : @identity.PolicyGeneration
  priv staleness : @staleness.StalenessEvidence?
  priv groups : CycleGroups
  priv mut usable_token_count : UInt64
  priv mut trainable_token_count : UInt64
  priv mut state : CycleState
  priv mut trainer_transaction : @trainer.TrainerTransaction?
  priv mut candidate : @update.CandidatePolicy?
  priv mut committed_policy : @identity.PolicyGeneration?
  priv mut abort_reason : CycleAbortReason?
}

///|
pub fn UpdateCycle::new(
  manifest : @experiment.ExperimentManifest,
  request : @rollout.RolloutGroupRequest,
) -> Self raise CycleError {
  if request.experiment() != manifest.identity() ||
    request.dataset() != manifest.dataset() ||
    request.actor() != manifest.actor() ||
    request.tokenizer() != manifest.tokenizer() ||
    request.rollout_count().to_uint64() >
    manifest.limits().rollouts_per_group().value() ||
    request.prompt_length().to_uint64() >
    manifest.limits().prompt_tokens().value() ||
    request.limits().maximum_response_tokens().to_uint64() >
    manifest.limits().response_tokens().value() {
    raise RequestMismatch
  }
  let maximum_groups = manifest.limits().concurrent_groups().value().to_int()
  let maximum_per_group = manifest
    .limits()
    .rollouts_per_group()
    .value()
    .to_int()
  if maximum_groups > 65536 / maximum_per_group {
    raise ExperimentLimitExceeded
  }
  let maximum_rollouts = maximum_groups * maximum_per_group
  let policy = manifest.actor()
  let round = @round.RoundOwner::new(policy, maximum_rollouts) catch {
    error => raise Round(error)
  }
  let groups = CycleGroups::new(maximum_groups, maximum_rollouts)
  groups.add(request)
  {
    manifest,
    round,
    training_policy: manifest.actor(),
    staleness: None,
    groups,
    usable_token_count: 0UL,
    trainable_token_count: 0UL,
    state: GatheringRollouts,
    trainer_transaction: None,
    candidate: None,
    committed_policy: None,
    abort_reason: None,
  }
}

///|
/// Opens a bounded off-policy update. The request owns source-policy rollout
/// evidence while the manifest actor is the exact policy being trained.
pub fn UpdateCycle::new_stale(
  manifest : @experiment.ExperimentManifest,
  request : @rollout.RolloutGroupRequest,
  staleness : @staleness.StalenessEvidence,
) -> Self raise CycleError {
  if request.experiment() != manifest.identity() ||
    request.dataset() != manifest.dataset() ||
    request.tokenizer() != manifest.tokenizer() ||
    staleness.source() != request.actor() ||
    staleness.target() != manifest.actor() ||
    !staleness.requires_correction() ||
    manifest.algorithm().kind() == GaePpo ||
    request.rollout_count().to_uint64() >
    manifest.limits().rollouts_per_group().value() ||
    request.prompt_length().to_uint64() >
    manifest.limits().prompt_tokens().value() ||
    request.limits().maximum_response_tokens().to_uint64() >
    manifest.limits().response_tokens().value() {
    raise RequestMismatch
  }
  let maximum_groups = manifest.limits().concurrent_groups().value().to_int()
  let maximum_per_group = manifest
    .limits()
    .rollouts_per_group()
    .value()
    .to_int()
  if maximum_groups > 65536 / maximum_per_group {
    raise ExperimentLimitExceeded
  }
  let maximum_rollouts = maximum_groups * maximum_per_group
  let round = @round.RoundOwner::new(request.actor(), maximum_rollouts) catch {
    error => raise Round(error)
  }
  let groups = CycleGroups::new(maximum_groups, maximum_rollouts)
  groups.add(request)
  {
    manifest,
    round,
    training_policy: manifest.actor(),
    staleness: Some(staleness),
    groups,
    usable_token_count: 0UL,
    trainable_token_count: 0UL,
    state: GatheringRollouts,
    trainer_transaction: None,
    candidate: None,
    committed_policy: None,
    abort_reason: None,
  }
}

///|
pub fn UpdateCycle::add_group(
  self : Self,
  request : @rollout.RolloutGroupRequest,
) -> Unit raise CycleError {
  self.require_state(GatheringRollouts)
  if request.experiment() != self.manifest.identity() ||
    request.dataset() != self.manifest.dataset() ||
    request.actor() != self.round.policy() ||
    request.tokenizer() != self.manifest.tokenizer() ||
    request.rollout_count().to_uint64() >
    self.manifest.limits().rollouts_per_group().value() ||
    request.prompt_length().to_uint64() >
    self.manifest.limits().prompt_tokens().value() ||
    request.limits().maximum_response_tokens().to_uint64() >
    self.manifest.limits().response_tokens().value() {
    raise RequestMismatch
  }
  self.groups.add(request)
}

///|
fn UpdateCycle::require_state(
  self : Self,
  expected : CycleState,
) -> Unit raise CycleError {
  if self.state != expected {
    raise InvalidState(expected~, actual=self.state)
  }
}

///|
pub fn UpdateCycle::admit_rollout(
  self : Self,
  response : @rollout.RolloutResponse,
) -> Unit raise CycleError {
  self.require_state(GatheringRollouts)
  if response.tokenizer() != self.manifest.tokenizer() {
    raise TokenizerMismatch
  }
  let trajectory = response.trajectory()
  if trajectory.prompt_length().to_uint64() >
    self.manifest.limits().prompt_tokens().value() ||
    trajectory.response_length().to_uint64() >
    self.manifest.limits().response_tokens().value() {
    raise ExperimentLimitExceeded
  }
  let terminal_is_usable = match response.terminal() {
    Complete | Partial(_) => true
    Cancelled(_) | Failed(_) => false
  }
  let response_tokens = trajectory.response_length().to_uint64()
  if terminal_is_usable &&
    response_tokens > 1073741824UL - self.usable_token_count {
    raise TrainerLimitExceeded
  }
  let usable = self.groups.record(response)
  if usable {
    self.round.admit(trajectory) catch {
      error => raise Round(error)
    }
    self.usable_token_count += response_tokens
  }
}

///|
pub fn UpdateCycle::seal_rollouts(self : Self) -> Unit raise CycleError {
  self.require_state(GatheringRollouts)
  self.groups.require_sealable()
  self.round.seal_rollouts() catch {
    error => raise Round(error)
  }
  self.state = AwaitingAdvantages
}

///|
pub fn UpdateCycle::accept_advantage(
  self : Self,
  evidence : @advantage.AdvantageEvidence,
) -> Unit raise CycleError {
  self.require_state(AwaitingAdvantages)
  if self.training_policy != self.round.policy() {
    raise CorrectionRequired
  }
  if evidence.reward_source().digest() != self.manifest.reward_policy().digest() {
    raise RewardPolicyMismatch
  }
  if evidence.algorithm() != self.manifest.algorithm() {
    raise AlgorithmMismatch
  }
  let trainable = evidence.trainable_token_count().to_uint64()
  if trainable > 134217728UL - self.trainable_token_count {
    raise TrainerLimitExceeded
  }
  self.round.accept_advantage(evidence) catch {
    error => raise Round(error)
  }
  self.trainable_token_count += trainable
  if self.round.state() == ReadyForTraining {
    self.state = ReadyForTraining
  }
}

///|
pub fn UpdateCycle::accept_ppo_target(
  self : Self,
  evidence : @advantage.PpoTargetEvidence,
) -> Unit raise CycleError {
  self.require_state(AwaitingAdvantages)
  if self.training_policy != self.round.policy() {
    raise CorrectionRequired
  }
  if evidence.reward_source().digest() != self.manifest.reward_policy().digest() {
    raise RewardPolicyMismatch
  }
  if evidence.algorithm() != self.manifest.algorithm() {
    raise AlgorithmMismatch
  }
  let trainable = evidence.trainable_token_count().to_uint64()
  if trainable > 134217728UL - self.trainable_token_count {
    raise TrainerLimitExceeded
  }
  self.round.accept_ppo_target(evidence) catch {
    error => raise Round(error)
  }
  self.trainable_token_count += trainable
  if self.round.state() == ReadyForTraining {
    self.state = ReadyForTraining
  }
}

///|
pub fn UpdateCycle::accept_corrected_advantage(
  self : Self,
  evidence : @correction.CorrectedAdvantageEvidence,
) -> Unit raise CycleError {
  self.require_state(AwaitingAdvantages)
  if self.training_policy == self.round.policy() {
    raise CorrectionMismatch
  }
  if evidence.source_policy() != self.round.policy() ||
    evidence.target_policy() != self.training_policy {
    raise CorrectionMismatch
  }
  guard self.staleness is Some(expected_staleness) &&
    evidence.staleness() == expected_staleness else {
    raise CorrectionMismatch
  }
  if evidence.reward_source().digest() != self.manifest.reward_policy().digest() {
    raise RewardPolicyMismatch
  }
  if evidence.algorithm() != self.manifest.algorithm() {
    raise AlgorithmMismatch
  }
  let trainable = evidence.training_item().trainable_token_count().to_uint64()
  if trainable > 134217728UL - self.trainable_token_count {
    raise TrainerLimitExceeded
  }
  self.round.accept_corrected_advantage(evidence) catch {
    error => raise Round(error)
  }
  self.trainable_token_count += trainable
  if self.round.state() == ReadyForTraining {
    self.state = ReadyForTraining
  }
}

///|
fn UpdateCycle::validate_batch(
  self : Self,
  batch : @update.TrainingBatch,
) -> Unit raise CycleError {
  if batch.policy() != self.training_policy {
    raise ForeignPolicy
  }
  if batch.item_count() != self.round.rollout_count() {
    raise BatchCoverageMismatch
  }
  for index in 0..<batch.item_count() {
    let item = batch.item_at(index) catch { _ => raise BatchCoverageMismatch }
    if !self.round.contains_rollout(item.rollout_id()) {
      raise BatchCoverageMismatch
    }
    if !self.round.training_evidence_matches(item) {
      raise TrainingShapeMismatch
    }
  }
}

///|
pub fn UpdateCycle::prepare_training(
  self : Self,
  request : @trainer.TrainingRequest,
) -> Unit raise CycleError {
  self.require_state(ReadyForTraining)
  self.validate_batch(request.batch())
  self.trainer_transaction = Some(@trainer.TrainerTransaction::new(request))
  self.state = TrainerPrepared
}

///|
pub fn UpdateCycle::dispatch_training(self : Self) -> Unit raise CycleError {
  self.require_state(TrainerPrepared)
  guard self.trainer_transaction is Some(transaction) else {
    raise InvalidState(expected=TrainerPrepared, actual=self.state)
  }
  transaction.dispatch() catch {
    error => raise Trainer(error)
  }
  self.state = TrainerDispatched
}

///|
pub fn UpdateCycle::accept_trainer_result(
  self : Self,
  result : @trainer.TrainerStepResult,
) -> Unit raise CycleError {
  self.require_state(TrainerDispatched)
  guard self.trainer_transaction is Some(transaction) else {
    raise InvalidState(expected=TrainerDispatched, actual=self.state)
  }
  transaction.accept_result(result) catch {
    error => raise Trainer(error)
  }
  transaction.complete() catch {
    error => raise Trainer(error)
  }
  self.candidate = Some(result.candidate())
  self.state = CandidateAccepted
}

///|
fn candidate_matches(
  left : @update.CandidatePolicy,
  right : @update.CandidatePolicy,
) -> Bool {
  left.parent() == right.parent() &&
  left.target() == right.target() &&
  left.artifact_digest() == right.artifact_digest() &&
  left.tensor_vocabulary_digest() == right.tensor_vocabulary_digest()
}

///|
pub fn UpdateCycle::accept_committed_publication(
  self : Self,
  publication : @publication.PublicationOwner,
) -> Unit raise CycleError {
  self.require_state(CandidateAccepted)
  if publication.state() != Committed {
    raise PublicationNotCommitted
  }
  guard self.candidate is Some(candidate) else {
    raise InvalidState(expected=CandidateAccepted, actual=self.state)
  }
  let manifest = publication.manifest()
  if !candidate_matches(manifest.candidate(), candidate) {
    raise PublicationMismatch
  }
  self.committed_policy = Some(candidate.target())
  self.state = PolicyCommitted
}

///|
pub fn UpdateCycle::finish(self : Self) -> Unit raise CycleError {
  self.require_state(PolicyCommitted)
  self.state = CycleCompleted
}

///|
fn abort_reason_for_round(reason : CycleAbortReason) -> @round.RoundAbortReason {
  match reason {
    RolloutFailure => RolloutFailure
    RewardFailure => RewardFailure
    TrainerFailure => TrainerFailure
    PublicationFailure => PublicationFailure
    OperatorRequested => OperatorRequested
  }
}

///|
pub fn UpdateCycle::abort(
  self : Self,
  reason : CycleAbortReason,
) -> Unit raise CycleError {
  match self.state {
    PolicyCommitted | CycleCompleted | CycleAborted =>
      raise InvalidState(expected=GatheringRollouts, actual=self.state)
    _ => ()
  }
  match self.trainer_transaction {
    Some(transaction) =>
      match transaction.state() {
        Prepared | Dispatched =>
          transaction.fail(Cancelled) catch {
            error => raise Trainer(error)
          }
        _ => ()
      }
    None => ()
  }
  self.round.abort(abort_reason_for_round(reason)) catch {
    error => raise Round(error)
  }
  self.abort_reason = Some(reason)
  self.state = CycleAborted
}
