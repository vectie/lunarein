///|
/// Teacher forcing always names the exact model being scored. A policy target
/// carries its generation lineage; a frozen reference carries its artifact
/// digest without inventing membership in the actor lineage.
pub(all) enum ScoreTarget {
  Policy(@identity.PolicyGeneration)
  Reference(@identity.Sha256Digest)
} derive(Debug, Eq)

///|
/// Immutable teacher-forcing work derived from one eligible rollout response.
pub struct TeacherScoreRequest {
  priv protocol_version : @version.ProtocolVersion
  priv request_id : ScoreRequestId
  priv rollout : RolloutResponse
  priv target : ScoreTarget
}

///|
pub fn TeacherScoreRequest::new(
  protocol_version~ : @version.ProtocolVersion,
  request_id~ : ScoreRequestId,
  rollout~ : RolloutResponse,
  target~ : ScoreTarget,
) -> Self raise RolloutProtocolError {
  require_supported_version(protocol_version)
  if protocol_version != rollout.protocol_version() {
    raise UnsupportedVersion
  }
  match rollout.terminal() {
    Complete | Partial(_) => ()
    Cancelled(_) | Failed(_) => raise IneligibleForScoring
  }
  let trajectory = rollout.trajectory()
  let mut trainable_tokens = 0
  for index in 0..<trajectory.response_length() {
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if token.is_trainable() {
      trainable_tokens += 1
    }
  }
  if trainable_tokens == 0 {
    raise NoTrainableTokens
  }
  { protocol_version, request_id, rollout, target, }
}

///|
pub fn TeacherScoreRequest::protocol_version(
  self : Self,
) -> @version.ProtocolVersion {
  self.protocol_version
}

///|
pub fn TeacherScoreRequest::request_id(self : Self) -> ScoreRequestId {
  self.request_id
}

///|
pub fn TeacherScoreRequest::rollout(self : Self) -> RolloutResponse {
  self.rollout
}

///|
pub fn TeacherScoreRequest::target(self : Self) -> ScoreTarget {
  self.target
}

///|
/// Token-aligned teacher-forced score. Environment-supplied tokens retain an
/// explicit unscored position instead of shortening a parallel logprob array.
pub struct TeacherTokenScore {
  priv model_logprob : Double?
} derive(Debug, Eq)

///|
pub fn TeacherTokenScore::model(
  model_logprob~ : Double,
) -> Self raise RolloutProtocolError {
  if model_logprob.is_nan() || model_logprob.is_inf() || model_logprob > 0.0 {
    raise InvalidScoreLogProbability(index=0)
  }
  { model_logprob: Some(model_logprob), }
}

///|
pub fn TeacherTokenScore::environment() -> Self {
  { model_logprob: None, }
}

///|
pub fn TeacherTokenScore::model_logprob(self : Self) -> Double? {
  self.model_logprob
}

///|
pub fn TeacherTokenScore::is_scored(self : Self) -> Bool {
  self.model_logprob is Some(_)
}

///|
/// Immutable score response evidence. Construction performs the full join
/// against the expected request before any evidence becomes usable.
pub struct TeacherScoreEvidence {
  priv protocol_version : @version.ProtocolVersion
  priv request_id : ScoreRequestId
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv tokenizer : @experiment.TokenizerIdentity
  priv target : ScoreTarget
  priv token_scores : ReadOnlyArray[TeacherTokenScore]
}

///|
pub fn TeacherScoreEvidence::new(
  protocol_version~ : @version.ProtocolVersion,
  request_id~ : ScoreRequestId,
  rollout_id~ : @identity.RolloutId,
  source_actor~ : @identity.PolicyGeneration,
  tokenizer~ : @experiment.TokenizerIdentity,
  target~ : ScoreTarget,
  token_scores~ : ArrayView[TeacherTokenScore],
  expected_request~ : TeacherScoreRequest,
) -> Self raise RolloutProtocolError {
  require_supported_version(protocol_version)
  let rollout = expected_request.rollout()
  let trajectory = rollout.trajectory()
  if protocol_version != expected_request.protocol_version() {
    raise UnsupportedVersion
  }
  if request_id != expected_request.request_id() ||
    rollout_id != trajectory.rollout_id() ||
    source_actor != trajectory.policy() ||
    tokenizer != rollout.tokenizer() ||
    target != expected_request.target() {
    raise ScoreIdentityMismatch
  }
  if token_scores.length() != trajectory.response_length() {
    raise ScoreLengthMismatch
  }
  for index, score in token_scores {
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    match (token.origin(), score.model_logprob()) {
      (ModelGenerated, Some(logprob)) =>
        if logprob.is_nan() || logprob.is_inf() || logprob > 0.0 {
          raise InvalidScoreLogProbability(index~)
        }
      (EnvironmentSupplied, None) => ()
      _ => raise ScoreOriginMismatch(index~)
    }
  }
  {
    protocol_version,
    request_id,
    trajectory: trajectory.evidence_identity(),
    tokenizer,
    target,
    token_scores: ReadOnlyArray::from_array(token_scores),
  }
}

///|
pub fn TeacherScoreEvidence::protocol_version(
  self : Self,
) -> @version.ProtocolVersion {
  self.protocol_version
}

///|
pub fn TeacherScoreEvidence::request_id(self : Self) -> ScoreRequestId {
  self.request_id
}

///|
pub fn TeacherScoreEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn TeacherScoreEvidence::source_actor(
  self : Self,
) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn TeacherScoreEvidence::tokenizer(
  self : Self,
) -> @experiment.TokenizerIdentity {
  self.tokenizer
}

///|
pub fn TeacherScoreEvidence::target(self : Self) -> ScoreTarget {
  self.target
}

///|
pub fn TeacherScoreEvidence::token_count(self : Self) -> Int32 {
  self.token_scores.length()
}

///|
pub fn TeacherScoreEvidence::token_score_at(
  self : Self,
  index : Int32,
) -> TeacherTokenScore raise RolloutProtocolError {
  if index < 0 || index >= self.token_scores.length() {
    raise ScoreLengthMismatch
  }
  self.token_scores[index]
}

///|
fn TeacherScoreEvidence::logprobs(self : Self) -> Array[Double?] {
  let values : Array[Double?] = []
  for score in self.token_scores {
    values.push(score.model_logprob())
  }
  values
}

///|
pub fn TeacherScoreEvidence::as_reference_score(
  self : Self,
  trajectory : @trajectory.Trajectory,
) -> @reward.ReferenceScoreEvidence raise RolloutProtocolError {
  guard self.target is Reference(reference_actor) else {
    raise ScoreTargetMismatch
  }
  if !self.trajectory.matches_trajectory(trajectory) {
    raise ScoreIdentityMismatch
  }
  @reward.ReferenceScoreEvidence::new(
    trajectory,
    reference_actor~,
    logprobs=self.logprobs(),
  ) catch {
    error => raise Reward(error)
  }
}

///|
pub fn TeacherScoreEvidence::as_policy_score(
  self : Self,
  trajectory : @trajectory.Trajectory,
) -> @reward.PolicyScoreEvidence raise RolloutProtocolError {
  guard self.target is Policy(target_policy) else { raise ScoreTargetMismatch }
  if !self.trajectory.matches_trajectory(trajectory) {
    raise ScoreIdentityMismatch
  }
  @reward.PolicyScoreEvidence::new(
    trajectory,
    target_policy~,
    logprobs=self.logprobs(),
  ) catch {
    error => raise Reward(error)
  }
}
