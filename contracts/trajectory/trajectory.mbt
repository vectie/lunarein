///|
pub(all) suberror TrajectoryError {
  InvalidLimit
  EmptyPrompt
  EmptyResponse
  InvalidTokenId(index~ : Int32)
  InvalidLogProbability(index~ : Int32)
  InconsistentTokenEvidence(index~ : Int32)
  InvalidTerminal
} derive(Debug, Eq)

///|
pub(all) enum TokenOrigin {
  ModelGenerated
  EnvironmentSupplied
} derive(Debug, Eq)

///|
pub struct RolloutToken {
  priv token_id : Int32
  priv origin : TokenOrigin
  priv model_logprob : Double?
  priv sampling_logprob : Double?
}

///|
fn validate_logprob(
  value : Double,
  index : Int32,
) -> Unit raise TrajectoryError {
  if value.is_nan() || value.is_inf() || value > 0.0 {
    raise InvalidLogProbability(index~)
  }
}

///|
pub fn RolloutToken::model(
  token_id~ : Int32,
  model_logprob~ : Double,
  sampling_logprob~ : Double,
  maximum_token_id~ : Int32,
) -> Self raise TrajectoryError {
  if token_id < 0 || token_id > maximum_token_id {
    raise InvalidTokenId(index=0)
  }
  validate_logprob(model_logprob, 0)
  validate_logprob(sampling_logprob, 0)
  {
    token_id,
    origin: ModelGenerated,
    model_logprob: Some(model_logprob),
    sampling_logprob: Some(sampling_logprob),
  }
}

///|
pub fn RolloutToken::environment(
  token_id~ : Int32,
  maximum_token_id~ : Int32,
) -> Self raise TrajectoryError {
  if token_id < 0 || token_id > maximum_token_id {
    raise InvalidTokenId(index=0)
  }
  {
    token_id,
    origin: EnvironmentSupplied,
    model_logprob: None,
    sampling_logprob: None,
  }
}

///|
pub fn RolloutToken::token_id(self : Self) -> Int32 {
  self.token_id
}

///|
pub fn RolloutToken::origin(self : Self) -> TokenOrigin {
  self.origin
}

///|
pub fn RolloutToken::model_logprob(self : Self) -> Double? {
  self.model_logprob
}

///|
pub fn RolloutToken::sampling_logprob(self : Self) -> Double? {
  self.sampling_logprob
}

///|
pub fn RolloutToken::is_trainable(self : Self) -> Bool {
  self.origin == ModelGenerated
}

///|
pub(all) enum TrajectoryTerminal {
  Completed
  Truncated
  Cancelled
  Failed
} derive(Debug, Eq)

///|
pub struct Trajectory {
  priv rollout_id : @identity.RolloutId
  priv group_id : @identity.GroupId
  priv policy : @identity.PolicyGeneration
  priv prompt_tokens : ReadOnlyArray[Int32]
  priv response_tokens : ReadOnlyArray[RolloutToken]
  priv terminal : TrajectoryTerminal
}

///|
pub fn Trajectory::new(
  rollout_id~ : @identity.RolloutId,
  group_id~ : @identity.GroupId,
  policy~ : @identity.PolicyGeneration,
  prompt_tokens~ : ArrayView[Int32],
  response_tokens~ : ArrayView[RolloutToken],
  terminal~ : TrajectoryTerminal,
  maximum_prompt_tokens~ : Int32,
  maximum_response_tokens~ : Int32,
  maximum_token_id~ : Int32,
) -> Self raise TrajectoryError {
  if maximum_prompt_tokens <= 0 ||
    maximum_response_tokens <= 0 ||
    maximum_token_id < 0 {
    raise InvalidLimit
  }
  if prompt_tokens.is_empty() {
    raise EmptyPrompt
  }
  if prompt_tokens.length() > maximum_prompt_tokens ||
    response_tokens.length() > maximum_response_tokens {
    raise InvalidLimit
  }
  if (terminal == Completed || terminal == Truncated) &&
    response_tokens.is_empty() {
    raise EmptyResponse
  }
  for index, token_id in prompt_tokens {
    if token_id < 0 || token_id > maximum_token_id {
      raise InvalidTokenId(index~)
    }
  }
  for index, token in response_tokens {
    if token.token_id() < 0 || token.token_id() > maximum_token_id {
      raise InvalidTokenId(index~)
    }
    match token.origin() {
      ModelGenerated => {
        guard token.model_logprob() is Some(model) &&
          token.sampling_logprob() is Some(sampling) else {
          raise InconsistentTokenEvidence(index~)
        }
        validate_logprob(model, index)
        validate_logprob(sampling, index)
      }
      EnvironmentSupplied =>
        if token.model_logprob() is Some(_) ||
          token.sampling_logprob() is Some(_) {
          raise InconsistentTokenEvidence(index~)
        }
    }
  }
  {
    rollout_id,
    group_id,
    policy,
    prompt_tokens: ReadOnlyArray::from_array(prompt_tokens),
    response_tokens: ReadOnlyArray::from_array(response_tokens),
    terminal,
  }
}

///|
pub fn Trajectory::rollout_id(self : Self) -> @identity.RolloutId {
  self.rollout_id
}

///|
pub fn Trajectory::group_id(self : Self) -> @identity.GroupId {
  self.group_id
}

///|
pub fn Trajectory::policy(self : Self) -> @identity.PolicyGeneration {
  self.policy
}

///|
pub fn Trajectory::prompt_length(self : Self) -> Int32 {
  self.prompt_tokens.length()
}

///|
pub fn Trajectory::prompt_token_at(
  self : Self,
  index : Int32,
) -> Int32 raise TrajectoryError {
  if index < 0 || index >= self.prompt_tokens.length() {
    raise InvalidTokenId(index~)
  }
  self.prompt_tokens[index]
}

///|
pub fn Trajectory::response_length(self : Self) -> Int32 {
  self.response_tokens.length()
}

///|
pub fn Trajectory::response_token_at(
  self : Self,
  index : Int32,
) -> RolloutToken raise TrajectoryError {
  if index < 0 || index >= self.response_tokens.length() {
    raise InvalidTokenId(index~)
  }
  self.response_tokens[index]
}

///|
pub fn Trajectory::terminal(self : Self) -> TrajectoryTerminal {
  self.terminal
}

///|
/// An exact, immutable identity for trajectory evidence. Unlike a caller-
/// supplied digest, this value is derived only from an already validated
/// trajectory and retains the canonical evidence needed to reject content,
/// group, prompt, token, log-probability, or terminal substitution.
pub struct TrajectoryEvidenceIdentity {
  priv trajectory : Trajectory
}

///|
pub fn Trajectory::evidence_identity(self : Self) -> TrajectoryEvidenceIdentity {
  { trajectory: self, }
}

///|
pub fn TrajectoryEvidenceIdentity::rollout_id(
  self : Self,
) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn TrajectoryEvidenceIdentity::group_id(self : Self) -> @identity.GroupId {
  self.trajectory.group_id()
}

///|
pub fn TrajectoryEvidenceIdentity::policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn TrajectoryEvidenceIdentity::response_length(self : Self) -> Int32 {
  self.trajectory.response_length()
}

///|
pub fn TrajectoryEvidenceIdentity::is_trainable_at(
  self : Self,
  index : Int32,
) -> Bool raise TrajectoryError {
  self.trajectory.response_token_at(index).is_trainable()
}

///|
fn same_optional_double(left : Double?, right : Double?) -> Bool {
  match (left, right) {
    (Some(left), Some(right)) => left == right
    (None, None) => true
    _ => false
  }
}

///|
fn same_token(left : RolloutToken, right : RolloutToken) -> Bool {
  left.token_id() == right.token_id() &&
  left.origin() == right.origin() &&
  same_optional_double(left.model_logprob(), right.model_logprob()) &&
  same_optional_double(left.sampling_logprob(), right.sampling_logprob())
}

///|
pub fn TrajectoryEvidenceIdentity::matches_trajectory(
  self : Self,
  other : Trajectory,
) -> Bool {
  let expected = self.trajectory
  if expected.rollout_id() != other.rollout_id() ||
    expected.group_id() != other.group_id() ||
    expected.policy() != other.policy() ||
    expected.terminal() != other.terminal() ||
    expected.prompt_length() != other.prompt_length() ||
    expected.response_length() != other.response_length() {
    return false
  }
  for index in 0..<expected.prompt_length() {
    let expected_token = try! expected.prompt_token_at(index)
    let actual_token = try! other.prompt_token_at(index)
    if expected_token != actual_token {
      return false
    }
  }
  for index in 0..<expected.response_length() {
    let expected_token = try! expected.response_token_at(index)
    let actual_token = try! other.response_token_at(index)
    if !same_token(expected_token, actual_token) {
      return false
    }
  }
  true
}

///|
pub fn TrajectoryEvidenceIdentity::same(
  self : Self,
  other : TrajectoryEvidenceIdentity,
) -> Bool {
  self.matches_trajectory(other.trajectory)
}
