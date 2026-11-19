///|
pub(all) enum PartialReason {
  ResponseTokenLimit
  DeadlineReached
  EnvironmentEnded
} derive(Debug, Eq)

///|
pub(all) enum CancellationReason {
  GroupSatisfied
  Superseded
  OperatorRequested
} derive(Debug, Eq)

///|
pub(all) enum FailureClass {
  InvalidRequest
  RuntimeUnavailable
  ResourceExhausted
  InternalFailure
} derive(Debug, Eq)

///|
/// Terminal evidence distinguishes usable partial output from cancellation or
/// failure. A cancelled response can retain partial tokens but cannot be
/// relabeled as completed evidence.
pub(all) enum RolloutTerminalEvidence {
  Complete
  Partial(PartialReason)
  Cancelled(CancellationReason)
  Failed(FailureClass)
} derive(Debug, Eq)

///|
fn terminal_matches(
  evidence : RolloutTerminalEvidence,
  terminal : @trajectory.TrajectoryTerminal,
) -> Bool {
  match (evidence, terminal) {
    (Complete, Completed) => true
    (Partial(_), Truncated) => true
    (Cancelled(_), Cancelled) => true
    (Failed(_), Failed) => true
    _ => false
  }
}

///|
/// Immutable runtime response evidence validated against the exact request and
/// deterministic rollout slot that authorized it.
pub struct RolloutResponse {
  priv protocol_version : @version.ProtocolVersion
  priv request_id : RolloutRequestId
  priv experiment : @experiment.ExperimentIdentity
  priv dataset : @experiment.DatasetIdentity
  priv tokenizer : @experiment.TokenizerIdentity
  priv sampling : SamplingIdentity
  priv trajectory : @trajectory.Trajectory
  priv terminal : RolloutTerminalEvidence
}

///|
pub fn RolloutResponse::new(
  protocol_version~ : @version.ProtocolVersion,
  request_id~ : RolloutRequestId,
  tokenizer~ : @experiment.TokenizerIdentity,
  sampling~ : SamplingIdentity,
  trajectory~ : @trajectory.Trajectory,
  terminal~ : RolloutTerminalEvidence,
  expected_request~ : RolloutGroupRequest,
) -> Self raise RolloutProtocolError {
  require_supported_version(protocol_version)
  if protocol_version != expected_request.protocol_version() {
    raise UnsupportedVersion
  }
  if request_id != expected_request.request_id() {
    raise RequestIdentityMismatch
  }
  if trajectory.group_id() != expected_request.group_id() {
    raise GroupIdentityMismatch
  }
  if trajectory.policy() != expected_request.actor() {
    raise ActorIdentityMismatch
  }
  if tokenizer != expected_request.tokenizer() {
    raise TokenizerIdentityMismatch
  }
  guard expected_request.slot_for_rollout(trajectory.rollout_id()) is Some(slot) else {
    raise UnknownRollout
  }
  if sampling != slot.sampling() {
    raise SamplingIdentityMismatch
  }
  if trajectory.prompt_length() != expected_request.prompt_length() {
    raise PromptMismatch
  }
  for index in 0..<trajectory.prompt_length() {
    let actual = trajectory.prompt_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if actual != expected_request.prompt_token_at(index) {
      raise PromptMismatch
    }
  }
  if trajectory.response_length() >
    expected_request.limits().maximum_response_tokens() {
    raise ResponseTooLong
  }
  for index in 0..<trajectory.response_length() {
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if token.token_id() < 0 ||
      token.token_id() > expected_request.limits().maximum_token_id() {
      raise ResponseTokenOutOfRange(index~)
    }
  }
  if !terminal_matches(terminal, trajectory.terminal()) {
    raise TerminalMismatch
  }
  {
    protocol_version,
    request_id,
    experiment: expected_request.experiment(),
    dataset: expected_request.dataset(),
    tokenizer,
    sampling,
    trajectory,
    terminal,
  }
}

///|
pub fn RolloutResponse::protocol_version(
  self : Self,
) -> @version.ProtocolVersion {
  self.protocol_version
}

///|
pub fn RolloutResponse::request_id(self : Self) -> RolloutRequestId {
  self.request_id
}

///|
pub fn RolloutResponse::tokenizer(self : Self) -> @experiment.TokenizerIdentity {
  self.tokenizer
}

///|
pub fn RolloutResponse::sampling(self : Self) -> SamplingIdentity {
  self.sampling
}

///|
pub fn RolloutResponse::trajectory(self : Self) -> @trajectory.Trajectory {
  self.trajectory
}

///|
pub fn RolloutResponse::terminal(self : Self) -> RolloutTerminalEvidence {
  self.terminal
}

///|
/// Revalidates this response against the exact request owned by a coordinator.
/// This prevents two caller-fabricated request IDs from making different
/// groups, prompts, slots, or sampling plans appear interchangeable.
pub fn RolloutResponse::matches_request(
  self : Self,
  expected : RolloutGroupRequest,
) -> Bool {
  if self.protocol_version != expected.protocol_version() ||
    self.request_id != expected.request_id() ||
    self.experiment != expected.experiment() ||
    self.dataset != expected.dataset() ||
    self.tokenizer != expected.tokenizer() ||
    self.trajectory.group_id() != expected.group_id() ||
    self.trajectory.policy() != expected.actor() ||
    self.trajectory.prompt_length() != expected.prompt_length() {
    return false
  }
  guard expected.slot_for_rollout(self.trajectory.rollout_id()) is Some(slot) else {
    return false
  }
  if self.sampling != slot.sampling() {
    return false
  }
  for index in 0..<self.trajectory.prompt_length() {
    let actual = self.trajectory.prompt_token_at(index) catch {
      _ => return false
    }
    let wanted = expected.prompt_token_at(index) catch { _ => return false }
    if actual != wanted {
      return false
    }
  }
  true
}
