///|
pub(all) suberror AdvantageError {
  InvalidDiscount
  InvalidTraceDecay
  InvalidKlCoefficient
  InvalidMinimumVariance
  AlgorithmMismatch
  EvidenceIdentityMismatch
  RewardSourceMismatch
  LengthMismatch
  NonFiniteValue(index~ : Int32)
  NonzeroEnvironmentTarget(index~ : Int32)
  InvalidTerminalBootstrap
  IneligibleTerminal
  NoTrainableTokens
  GroupTooSmall
  MixedGroup
  MixedPolicy
  MixedRewardSource
  DuplicateRollout
  DegenerateGroup
  InvalidIndex(index~ : Int32)
  Reward(@reward.RewardError)
  Trajectory(@trajectory.TrajectoryError)
} derive(Debug, Eq)

///|
pub struct AdvantageEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv reward_source : @reward.RewardSourceId
  priv algorithm : @experiment.AlgorithmIdentity
  priv values : ReadOnlyArray[Double]
  priv trainable_token_count : Int32
}

///|
fn AdvantageEvidence::validated(
  trajectory : @trajectory.Trajectory,
  reward_source : @reward.RewardSourceId,
  algorithm : @experiment.AlgorithmIdentity,
  values : ArrayView[Double],
) -> AdvantageEvidence raise AdvantageError {
  if values.length() != trajectory.response_length() {
    raise LengthMismatch
  }
  let mut trainable_token_count = 0
  for index, value in values {
    if value.is_nan() || value.is_inf() {
      raise NonFiniteValue(index~)
    }
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if token.is_trainable() {
      trainable_token_count += 1
    } else if value != 0.0 {
      raise NonzeroEnvironmentTarget(index~)
    }
  }
  if trainable_token_count == 0 {
    raise NoTrainableTokens
  }
  {
    trajectory: trajectory.evidence_identity(),
    reward_source,
    algorithm,
    values: ReadOnlyArray::from_array(values),
    trainable_token_count,
  }
}

///|
pub fn AdvantageEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn AdvantageEvidence::policy(self : Self) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn AdvantageEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn AdvantageEvidence::reward_source(self : Self) -> @reward.RewardSourceId {
  self.reward_source
}

///|
pub fn AdvantageEvidence::algorithm(
  self : Self,
) -> @experiment.AlgorithmIdentity {
  self.algorithm
}

///|
pub fn AdvantageEvidence::token_count(self : Self) -> Int32 {
  self.values.length()
}

///|
pub fn AdvantageEvidence::trainable_token_count(self : Self) -> Int32 {
  self.trainable_token_count
}

///|
pub fn AdvantageEvidence::value_at(
  self : Self,
  index : Int32,
) -> Double raise AdvantageError {
  if index < 0 || index >= self.values.length() {
    raise InvalidIndex(index~)
  }
  self.values[index]
}

///|
pub fn AdvantageEvidence::training_item(
  self : Self,
) -> @update.TrainingItemRef raise AdvantageError {
  @update.TrainingItemRef::new(
    trajectory=self.trajectory,
    target_values=self.values,
  ) catch {
    _ => raise EvidenceIdentityMismatch
  }
}

///|
pub fn AdvantageEvidence::matches_training_item(
  self : Self,
  item : @update.TrainingItemRef,
) -> Bool {
  if !self.trajectory.same(item.trajectory_identity()) ||
    self.values.length() != item.token_count() ||
    self.trainable_token_count != item.trainable_token_count() {
    return false
  }
  for index in 0..<self.values.length() {
    let value = item.target_value_at(index) catch { _ => return false }
    if value != self.values[index] {
      return false
    }
  }
  true
}

///|
/// State values before each response token plus one bootstrap value after the
/// final token. Completed trajectories require a zero terminal bootstrap;
/// truncated trajectories retain an explicit bootstrap estimate.
pub struct StateValueEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv values : ReadOnlyArray[Double]
}

///|
pub fn StateValueEvidence::new(
  trajectory : @trajectory.Trajectory,
  values~ : ArrayView[Double],
) -> Self raise AdvantageError {
  require_eligible(trajectory)
  if values.length() != trajectory.response_length() + 1 {
    raise LengthMismatch
  }
  for index, value in values {
    if value.is_nan() || value.is_inf() {
      raise NonFiniteValue(index~)
    }
  }
  if trajectory.terminal() == Completed && values[values.length() - 1] != 0.0 {
    raise InvalidTerminalBootstrap
  }
  {
    trajectory: trajectory.evidence_identity(),
    values: ReadOnlyArray::from_array(values),
  }
}

///|
pub fn StateValueEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn StateValueEvidence::policy(self : Self) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn StateValueEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn StateValueEvidence::value_count(self : Self) -> Int32 {
  self.values.length()
}

///|
pub fn StateValueEvidence::value_at(
  self : Self,
  index : Int32,
) -> Double raise AdvantageError {
  if index < 0 || index >= self.values.length() {
    raise InvalidIndex(index~)
  }
  self.values[index]
}

///|
/// Exact PPO policy and value targets. Both arrays are response-aligned and
/// contain zero at environment-token positions.
pub struct PpoTargetEvidence {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv reward_source : @reward.RewardSourceId
  priv algorithm : @experiment.AlgorithmIdentity
  priv advantages : ReadOnlyArray[Double]
  priv value_returns : ReadOnlyArray[Double]
  priv trainable_token_count : Int32
}

///|
fn PpoTargetEvidence::validated(
  trajectory : @trajectory.Trajectory,
  reward_source : @reward.RewardSourceId,
  algorithm : @experiment.AlgorithmIdentity,
  advantages : ArrayView[Double],
  value_returns : ArrayView[Double],
) -> PpoTargetEvidence raise AdvantageError {
  if advantages.length() != trajectory.response_length() ||
    value_returns.length() != trajectory.response_length() {
    raise LengthMismatch
  }
  let mut trainable_token_count = 0
  for index in 0..<advantages.length() {
    let advantage = advantages[index]
    let value_return = value_returns[index]
    if advantage.is_nan() || advantage.is_inf() {
      raise NonFiniteValue(index~)
    }
    if value_return.is_nan() || value_return.is_inf() {
      raise NonFiniteValue(index~)
    }
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if token.is_trainable() {
      trainable_token_count += 1
    } else if advantage != 0.0 || value_return != 0.0 {
      raise NonzeroEnvironmentTarget(index~)
    }
  }
  if trainable_token_count == 0 {
    raise NoTrainableTokens
  }
  {
    trajectory: trajectory.evidence_identity(),
    reward_source,
    algorithm,
    advantages: ReadOnlyArray::from_array(advantages),
    value_returns: ReadOnlyArray::from_array(value_returns),
    trainable_token_count,
  }
}

///|
pub fn PpoTargetEvidence::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn PpoTargetEvidence::policy(self : Self) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn PpoTargetEvidence::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn PpoTargetEvidence::reward_source(self : Self) -> @reward.RewardSourceId {
  self.reward_source
}

///|
pub fn PpoTargetEvidence::algorithm(
  self : Self,
) -> @experiment.AlgorithmIdentity {
  self.algorithm
}

///|
pub fn PpoTargetEvidence::token_count(self : Self) -> Int32 {
  self.advantages.length()
}

///|
pub fn PpoTargetEvidence::trainable_token_count(self : Self) -> Int32 {
  self.trainable_token_count
}

///|
pub fn PpoTargetEvidence::advantage_at(
  self : Self,
  index : Int32,
) -> Double raise AdvantageError {
  if index < 0 || index >= self.advantages.length() {
    raise InvalidIndex(index~)
  }
  self.advantages[index]
}

///|
pub fn PpoTargetEvidence::value_return_at(
  self : Self,
  index : Int32,
) -> Double raise AdvantageError {
  if index < 0 || index >= self.value_returns.length() {
    raise InvalidIndex(index~)
  }
  self.value_returns[index]
}

///|
pub fn PpoTargetEvidence::training_item(
  self : Self,
) -> @update.TrainingItemRef raise AdvantageError {
  @update.TrainingItemRef::ppo(
    trajectory=self.trajectory,
    advantages=self.advantages,
    value_returns=self.value_returns,
  ) catch {
    _ => raise EvidenceIdentityMismatch
  }
}

///|
pub fn PpoTargetEvidence::matches_training_item(
  self : Self,
  item : @update.TrainingItemRef,
) -> Bool {
  if !self.trajectory.same(item.trajectory_identity()) ||
    self.advantages.length() != item.token_count() ||
    self.trainable_token_count != item.trainable_token_count() ||
    !item.has_value_returns() {
    return false
  }
  for index in 0..<self.advantages.length() {
    let advantage = item.target_value_at(index) catch { _ => return false }
    let value_return = item.value_return_at(index) catch { _ => return false }
    if advantage != self.advantages[index] ||
      value_return != Some(self.value_returns[index]) {
      return false
    }
  }
  true
}

///|
fn require_eligible(
  trajectory : @trajectory.Trajectory,
) -> Unit raise AdvantageError {
  match trajectory.terminal() {
    Completed | Truncated => ()
    Cancelled | Failed => raise IneligibleTerminal
  }
}
