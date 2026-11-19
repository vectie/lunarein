///|
fn validate_discount(discount : Double) -> Unit raise AdvantageError {
  if discount.is_nan() || discount.is_inf() || discount < 0.0 || discount > 1.0 {
    raise InvalidDiscount
  }
}

///|
fn require_scalar_match(
  trajectory : @trajectory.Trajectory,
  scalar : @reward.ScalarRewardEvidence,
) -> Unit raise AdvantageError {
  if !scalar.trajectory_identity().matches_trajectory(trajectory) {
    raise EvidenceIdentityMismatch
  }
}

///|
fn require_token_match(
  trajectory : @trajectory.Trajectory,
  token_rewards : @reward.TokenRewardEvidence,
) -> Unit raise AdvantageError {
  if !token_rewards.trajectory_identity().matches_trajectory(trajectory) ||
    token_rewards.token_count() != trajectory.response_length() {
    raise EvidenceIdentityMismatch
  }
}

///|
fn require_reward_pair(
  trajectory : @trajectory.Trajectory,
  scalar : @reward.ScalarRewardEvidence,
  token_rewards : @reward.TokenRewardEvidence,
) -> Unit raise AdvantageError {
  require_eligible(trajectory)
  require_scalar_match(trajectory, scalar)
  require_token_match(trajectory, token_rewards)
  if scalar.source() != token_rewards.source() {
    raise RewardSourceMismatch
  }
}

///|
fn require_reference_match(
  trajectory : @trajectory.Trajectory,
  reference : @reward.ReferenceScoreEvidence,
) -> Unit raise AdvantageError {
  if !reference.trajectory_identity().matches_trajectory(trajectory) ||
    reference.token_count() != trajectory.response_length() {
    raise EvidenceIdentityMismatch
  }
}

///|
fn token_reward_at(
  rewards : @reward.TokenRewardEvidence,
  index : Int32,
) -> Double raise AdvantageError {
  rewards.value_at(index) catch {
    error => raise Reward(error)
  }
}

///|
fn reference_logprob_at(
  reference : @reward.ReferenceScoreEvidence,
  index : Int32,
) -> Double? raise AdvantageError {
  reference.logprob_at(index) catch {
    error => raise Reward(error)
  }
}

///|
fn make_reinforce_returns(
  trajectory : @trajectory.Trajectory,
  scalar : @reward.ScalarRewardEvidence,
  token_rewards : @reward.TokenRewardEvidence,
  discount : Double,
  reference : @reward.ReferenceScoreEvidence?,
  kl_coefficient : Double,
  algorithm : @experiment.AlgorithmIdentity,
) -> AdvantageEvidence raise AdvantageError {
  let token_count = trajectory.response_length()
  let values = Array::make(token_count, 0.0)
  let mut running_return = 0.0
  for reverse_index in 0..<token_count {
    let index = token_count - reverse_index - 1
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    let mut reward_value = token_reward_at(token_rewards, index)
    if index == token_count - 1 {
      reward_value += scalar.value()
    }
    match reference {
      Some(scores) if token.is_trainable() => {
        guard token.model_logprob() is Some(actor_logprob) &&
          reference_logprob_at(scores, index) is Some(reference_logprob) else {
          raise EvidenceIdentityMismatch
        }
        reward_value -= kl_coefficient * (actor_logprob - reference_logprob)
      }
      _ => ()
    }
    running_return = reward_value + discount * running_return
    if token.is_trainable() {
      values[index] = running_return
    }
  }
  AdvantageEvidence::validated(trajectory, scalar.source(), algorithm, values)
}

///|
/// Deterministic reward-to-go targets for REINFORCE. Scalar reward is applied
/// at the final response event and token rewards remain response-aligned.
pub fn reinforce_returns(
  trajectory : @trajectory.Trajectory,
  scalar : @reward.ScalarRewardEvidence,
  token_rewards : @reward.TokenRewardEvidence,
  discount~ : Double,
  algorithm~ : @experiment.AlgorithmIdentity,
) -> AdvantageEvidence raise AdvantageError {
  if algorithm.kind() != Reinforce {
    raise AlgorithmMismatch
  }
  validate_discount(discount)
  require_reward_pair(trajectory, scalar, token_rewards)
  make_reinforce_returns(
    trajectory,
    scalar,
    token_rewards,
    discount,
    None,
    0.0,
    algorithm,
  )
}

///|
/// REINFORCE returns with an explicit sampled per-token KL estimate
/// `actor_model_logprob - reference_logprob` on model-generated tokens.
pub fn reinforce_returns_with_reference_kl(
  trajectory : @trajectory.Trajectory,
  scalar : @reward.ScalarRewardEvidence,
  token_rewards : @reward.TokenRewardEvidence,
  reference : @reward.ReferenceScoreEvidence,
  discount~ : Double,
  kl_coefficient~ : Double,
  algorithm~ : @experiment.AlgorithmIdentity,
) -> AdvantageEvidence raise AdvantageError {
  if algorithm.kind() != ReinforceReferenceKl {
    raise AlgorithmMismatch
  }
  validate_discount(discount)
  if kl_coefficient.is_nan() || kl_coefficient.is_inf() || kl_coefficient < 0.0 {
    raise InvalidKlCoefficient
  }
  require_reward_pair(trajectory, scalar, token_rewards)
  require_reference_match(trajectory, reference)
  make_reinforce_returns(
    trajectory,
    scalar,
    token_rewards,
    discount,
    Some(reference),
    kl_coefficient,
    algorithm,
  )
}

///|
/// Deterministic GRPO population normalization for one prompt group. Each
/// normalized scalar is copied only to model-generated token positions.
pub fn grpo_group_normalize(
  trajectories : ArrayView[@trajectory.Trajectory],
  scalar_rewards : ArrayView[@reward.ScalarRewardEvidence],
  minimum_variance~ : Double,
  algorithm~ : @experiment.AlgorithmIdentity,
) -> Array[AdvantageEvidence] raise AdvantageError {
  if algorithm.kind() != Grpo {
    raise AlgorithmMismatch
  }
  if minimum_variance.is_nan() ||
    minimum_variance.is_inf() ||
    minimum_variance <= 0.0 {
    raise InvalidMinimumVariance
  }
  if trajectories.length() != scalar_rewards.length() {
    raise LengthMismatch
  }
  if trajectories.length() < 2 {
    raise GroupTooSmall
  }
  let first_trajectory = trajectories[0]
  let first_reward = scalar_rewards[0]
  require_eligible(first_trajectory)
  require_scalar_match(first_trajectory, first_reward)
  let group_id = first_trajectory.group_id()
  let policy = first_trajectory.policy()
  let source = first_reward.source()
  let mut sum = 0.0
  for index, trajectory in trajectories {
    require_eligible(trajectory)
    let reward = scalar_rewards[index]
    require_scalar_match(trajectory, reward)
    if trajectory.group_id() != group_id {
      raise MixedGroup
    }
    if trajectory.policy() != policy {
      raise MixedPolicy
    }
    if reward.source() != source {
      raise MixedRewardSource
    }
    for previous in 0..<index {
      if trajectories[previous].rollout_id() == trajectory.rollout_id() {
        raise DuplicateRollout
      }
    }
    sum += reward.value()
  }
  let count = trajectories.length().to_double()
  let mean = sum / count
  let mut squared_deviation_sum = 0.0
  for reward in scalar_rewards {
    let deviation = reward.value() - mean
    squared_deviation_sum += deviation * deviation
  }
  let variance = squared_deviation_sum / count
  if variance.is_nan() || variance.is_inf() || variance <= minimum_variance {
    raise DegenerateGroup
  }
  let standard_deviation = variance.sqrt()
  let outputs : Array[AdvantageEvidence] = []
  for index, trajectory in trajectories {
    let normalized = (scalar_rewards[index].value() - mean) / standard_deviation
    let values = Array::make(trajectory.response_length(), 0.0)
    for token_index in 0..<trajectory.response_length() {
      let token = trajectory.response_token_at(token_index) catch {
        error => raise Trajectory(error)
      }
      if token.is_trainable() {
        values[token_index] = normalized
      }
    }
    outputs.push(
      AdvantageEvidence::validated(trajectory, source, algorithm, values),
    )
  }
  outputs
}

///|
/// Generalized advantage estimation and aligned PPO value returns. Environment
/// events participate in temporal propagation but receive zero trainable
/// targets in the output.
pub fn gae_ppo_targets(
  trajectory : @trajectory.Trajectory,
  scalar : @reward.ScalarRewardEvidence,
  token_rewards : @reward.TokenRewardEvidence,
  state_values : StateValueEvidence,
  discount~ : Double,
  trace_decay~ : Double,
  algorithm~ : @experiment.AlgorithmIdentity,
) -> PpoTargetEvidence raise AdvantageError {
  if algorithm.kind() != GaePpo {
    raise AlgorithmMismatch
  }
  validate_discount(discount)
  if trace_decay.is_nan() ||
    trace_decay.is_inf() ||
    trace_decay < 0.0 ||
    trace_decay > 1.0 {
    raise InvalidTraceDecay
  }
  require_reward_pair(trajectory, scalar, token_rewards)
  if !state_values.trajectory_identity().matches_trajectory(trajectory) ||
    state_values.value_count() != trajectory.response_length() + 1 {
    raise EvidenceIdentityMismatch
  }
  let token_count = trajectory.response_length()
  let advantages = Array::make(token_count, 0.0)
  let value_returns = Array::make(token_count, 0.0)
  let mut running_advantage = 0.0
  for reverse_index in 0..<token_count {
    let index = token_count - reverse_index - 1
    let mut reward_value = token_reward_at(token_rewards, index)
    if index == token_count - 1 {
      reward_value += scalar.value()
    }
    let current_value = state_values.value_at(index)
    let next_value = state_values.value_at(index + 1)
    let delta = reward_value + discount * next_value - current_value
    running_advantage = delta + discount * trace_decay * running_advantage
    let token = trajectory.response_token_at(index) catch {
      error => raise Trajectory(error)
    }
    if token.is_trainable() {
      advantages[index] = running_advantage
      value_returns[index] = running_advantage + current_value
    }
  }
  PpoTargetEvidence::validated(
    trajectory,
    scalar.source(),
    algorithm,
    advantages,
    value_returns,
  )
}
