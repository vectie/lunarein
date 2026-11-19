///|
pub(all) suberror RewardError {
  NonFiniteScalarReward
  TokenRewardLengthMismatch
  NonFiniteTokenReward(index~ : Int32)
  ReferenceScoreLengthMismatch
  InvalidReferenceScore(index~ : Int32)
  InconsistentReferenceScore(index~ : Int32)
  IneligibleTerminal
  InvalidIndex(index~ : Int32)
  Trajectory(@trajectory.TrajectoryError)
} derive(Debug, Eq)

///|
/// A content identity for the exact reward definition that emitted evidence.
/// It may identify a model, verifier, or deterministic rule bundle.
pub struct RewardSourceId {
  priv digest : @identity.Sha256Digest
} derive(Debug, Eq)

///|
pub fn RewardSourceId::new(digest : @identity.Sha256Digest) -> Self {
  { digest, }
}

///|
pub fn RewardSourceId::digest(self : Self) -> @identity.Sha256Digest {
  self.digest
}

///|
fn require_eligible(
  trajectory : @trajectory.Trajectory,
) -> Unit raise RewardError {
  match trajectory.terminal() {
    Completed | Truncated => ()
    Cancelled | Failed => raise IneligibleTerminal
  }
}

///|
/// One scalar reward bound to an exact rollout, actor generation, and reward
/// source. Reward evidence never mutates its trajectory.
pub struct ScalarRewardEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv source : RewardSourceId
  priv value : Double
}

///|
pub fn ScalarRewardEvidence::new(
  trajectory : @trajectory.Trajectory,
  source~ : RewardSourceId,
  value~ : Double,
) -> Self raise RewardError {
  require_eligible(trajectory)
  if value.is_nan() || value.is_inf() {
    raise NonFiniteScalarReward
  }
  { trajectory: trajectory.evidence_identity(), source, value, }
}

///|
pub fn ScalarRewardEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn ScalarRewardEvidence::policy(self : Self) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn ScalarRewardEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn ScalarRewardEvidence::source(self : Self) -> RewardSourceId {
  self.source
}

///|
pub fn ScalarRewardEvidence::value(self : Self) -> Double {
  self.value
}

///|
/// Token-aligned rewards. Environment-token rewards are retained because they
/// can causally affect earlier model actions; trainability is derived later
/// from token origin rather than encoded as a caller-supplied mask.
pub struct TokenRewardEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv source : RewardSourceId
  priv values : ReadOnlyArray[Double]
}

///|
pub fn TokenRewardEvidence::new(
  trajectory : @trajectory.Trajectory,
  source~ : RewardSourceId,
  values~ : ArrayView[Double],
) -> Self raise RewardError {
  require_eligible(trajectory)
  if values.length() != trajectory.response_length() {
    raise TokenRewardLengthMismatch
  }
  for index, value in values {
    if value.is_nan() || value.is_inf() {
      raise NonFiniteTokenReward(index~)
    }
  }
  {
    trajectory: trajectory.evidence_identity(),
    source,
    values: ReadOnlyArray::from_array(values),
  }
}

///|
pub fn TokenRewardEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn TokenRewardEvidence::policy(self : Self) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn TokenRewardEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn TokenRewardEvidence::source(self : Self) -> RewardSourceId {
  self.source
}

///|
pub fn TokenRewardEvidence::token_count(self : Self) -> Int32 {
  self.values.length()
}

///|
pub fn TokenRewardEvidence::value_at(
  self : Self,
  index : Int32,
) -> Double raise RewardError {
  if index < 0 || index >= self.values.length() {
    raise InvalidIndex(index~)
  }
  self.values[index]
}

///|
/// Teacher-forced log probabilities from one exact reference actor. Model
/// tokens carry finite normalized log probabilities; environment tokens carry
/// no reference score.
pub struct ReferenceScoreEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv reference_actor : @identity.Sha256Digest
  priv logprobs : ReadOnlyArray[Double?]
}

///|
pub fn ReferenceScoreEvidence::new(
  trajectory : @trajectory.Trajectory,
  reference_actor~ : @identity.Sha256Digest,
  logprobs~ : ArrayView[Double?],
) -> Self raise RewardError {
  require_eligible(trajectory)
  if logprobs.length() != trajectory.response_length() {
    raise ReferenceScoreLengthMismatch
  }
  for index, score in logprobs {
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    match (token.is_trainable(), score) {
      (true, Some(value)) =>
        if value.is_nan() || value.is_inf() || value > 0.0 {
          raise InvalidReferenceScore(index~)
        }
      (false, None) => ()
      _ => raise InconsistentReferenceScore(index~)
    }
  }
  {
    trajectory: trajectory.evidence_identity(),
    reference_actor,
    logprobs: ReadOnlyArray::from_array(logprobs),
  }
}

///|
pub fn ReferenceScoreEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn ReferenceScoreEvidence::policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn ReferenceScoreEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn ReferenceScoreEvidence::reference_actor(
  self : Self,
) -> @identity.Sha256Digest {
  self.reference_actor
}

///|
pub fn ReferenceScoreEvidence::token_count(self : Self) -> Int32 {
  self.logprobs.length()
}

///|
pub fn ReferenceScoreEvidence::logprob_at(
  self : Self,
  index : Int32,
) -> Double? raise RewardError {
  if index < 0 || index >= self.logprobs.length() {
    raise InvalidIndex(index~)
  }
  self.logprobs[index]
}

///|
/// Teacher-forced log probabilities under an exact target policy generation.
/// This is distinct from a frozen reference actor because the target retains
/// policy lineage and can therefore support bounded off-policy correction.
pub struct PolicyScoreEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv target_policy : @identity.PolicyGeneration
  priv logprobs : ReadOnlyArray[Double?]
}

///|
pub fn PolicyScoreEvidence::new(
  trajectory : @trajectory.Trajectory,
  target_policy~ : @identity.PolicyGeneration,
  logprobs~ : ArrayView[Double?],
) -> Self raise RewardError {
  require_eligible(trajectory)
  if logprobs.length() != trajectory.response_length() {
    raise ReferenceScoreLengthMismatch
  }
  for index, score in logprobs {
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    match (token.is_trainable(), score) {
      (true, Some(value)) =>
        if value.is_nan() || value.is_inf() || value > 0.0 {
          raise InvalidReferenceScore(index~)
        }
      (false, None) => ()
      _ => raise InconsistentReferenceScore(index~)
    }
  }
  {
    trajectory: trajectory.evidence_identity(),
    target_policy,
    logprobs: ReadOnlyArray::from_array(logprobs),
  }
}

///|
pub fn PolicyScoreEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn PolicyScoreEvidence::source_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn PolicyScoreEvidence::target_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.target_policy
}

///|
pub fn PolicyScoreEvidence::token_count(self : Self) -> Int32 {
  self.logprobs.length()
}

///|
pub fn PolicyScoreEvidence::logprob_at(
  self : Self,
  index : Int32,
) -> Double? raise RewardError {
  if index < 0 || index >= self.logprobs.length() {
    raise InvalidIndex(index~)
  }
  self.logprobs[index]
}
