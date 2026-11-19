///|
pub struct TrainingItemRef {
  priv trajectory : @trajectory.TrajectoryEvidenceIdentity
  priv training_policy : @identity.PolicyGeneration
  priv target_values : ReadOnlyArray[Double]
  priv value_returns : ReadOnlyArray[Double]?
  priv trainable_token_count : Int32
}

///|
pub fn TrainingItemRef::new(
  trajectory~ : @trajectory.TrajectoryEvidenceIdentity,
  target_values~ : ArrayView[Double],
) -> Self raise UpdateError {
  let token_count = trajectory.response_length()
  if token_count <= 0 || target_values.length() != token_count {
    raise InvalidTokenCount
  }
  let mut trainable_token_count = 0
  for index, value in target_values {
    if value.is_nan() || value.is_inf() {
      raise NonFiniteTrainingTarget(index~)
    }
    let trainable = trajectory.is_trainable_at(index) catch {
      _ => raise InvalidTokenCount
    }
    if trainable {
      trainable_token_count += 1
    } else if value != 0.0 {
      raise NonzeroEnvironmentTarget(index~)
    }
  }
  if trainable_token_count == 0 {
    raise InvalidTokenCount
  }
  {
    trajectory,
    training_policy: trajectory.policy(),
    target_values: ReadOnlyArray::from_array(target_values),
    value_returns: None,
    trainable_token_count,
  }
}

///|
pub fn TrainingItemRef::ppo(
  trajectory~ : @trajectory.TrajectoryEvidenceIdentity,
  advantages~ : ArrayView[Double],
  value_returns~ : ArrayView[Double],
) -> Self raise UpdateError {
  let policy_item = TrainingItemRef::new(trajectory~, target_values=advantages)
  if value_returns.length() != policy_item.token_count() {
    raise InvalidTokenCount
  }
  for index, value in value_returns {
    if value.is_nan() || value.is_inf() {
      raise NonFiniteTrainingTarget(index~)
    }
    let trainable = trajectory.is_trainable_at(index) catch {
      _ => raise InvalidTokenCount
    }
    if !trainable && value != 0.0 {
      raise NonzeroEnvironmentTarget(index~)
    }
  }
  {
    trajectory,
    training_policy: trajectory.policy(),
    target_values: policy_item.target_values,
    value_returns: Some(ReadOnlyArray::from_array(value_returns)),
    trainable_token_count: policy_item.trainable_token_count,
  }
}

///|
/// A policy-gradient target corrected from an older trajectory for an exact
/// newer training policy. The caller must still present the typed correction
/// evidence to the cycle; this constructor only validates target shape.
pub fn TrainingItemRef::corrected(
  trajectory~ : @trajectory.TrajectoryEvidenceIdentity,
  training_policy~ : @identity.PolicyGeneration,
  target_values~ : ArrayView[Double],
) -> Self raise UpdateError {
  let source_item = TrainingItemRef::new(trajectory~, target_values~)
  {
    trajectory,
    training_policy,
    target_values: source_item.target_values,
    value_returns: None,
    trainable_token_count: source_item.trainable_token_count,
  }
}

///|
pub fn TrainingItemRef::rollout_id(self : Self) -> @identity.RolloutId {
  self.trajectory.rollout_id()
}

///|
pub fn TrainingItemRef::policy(self : Self) -> @identity.PolicyGeneration {
  self.training_policy
}

///|
pub fn TrainingItemRef::source_policy(
  self : Self,
) -> @identity.PolicyGeneration {
  self.trajectory.policy()
}

///|
pub fn TrainingItemRef::trajectory_identity(
  self : Self,
) -> @trajectory.TrajectoryEvidenceIdentity {
  self.trajectory
}

///|
pub fn TrainingItemRef::token_count(self : Self) -> Int32 {
  self.target_values.length()
}

///|
pub fn TrainingItemRef::trainable_token_count(self : Self) -> Int32 {
  self.trainable_token_count
}

///|
pub fn TrainingItemRef::target_value_at(
  self : Self,
  index : Int32,
) -> Double raise UpdateError {
  if index < 0 || index >= self.target_values.length() {
    raise InvalidTokenCount
  }
  self.target_values[index]
}

///|
pub fn TrainingItemRef::has_value_returns(self : Self) -> Bool {
  self.value_returns is Some(_)
}

///|
pub fn TrainingItemRef::value_return_at(
  self : Self,
  index : Int32,
) -> Double? raise UpdateError {
  if index < 0 || index >= self.target_values.length() {
    raise InvalidTokenCount
  }
  match self.value_returns {
    Some(values) => Some(values[index])
    None => None
  }
}

///|
pub struct TrainingBatch {
  priv id : TrainingBatchId
  priv policy : @identity.PolicyGeneration
  priv items : ReadOnlyArray[TrainingItemRef]
  priv total_token_count : Int32
  priv trainable_token_count : Int32
}

///|
pub fn TrainingBatch::new(
  id~ : TrainingBatchId,
  policy~ : @identity.PolicyGeneration,
  items~ : ArrayView[TrainingItemRef],
  maximum_items~ : Int32,
  maximum_total_tokens~ : Int32,
  maximum_trainable_tokens~ : Int32,
) -> Self raise UpdateError {
  if maximum_items <= 0 ||
    maximum_items > 65536 ||
    maximum_total_tokens <= 0 ||
    maximum_total_tokens > 1073741824 ||
    maximum_trainable_tokens <= 0 ||
    maximum_trainable_tokens > 134217728 {
    raise InvalidLimit
  }
  if items.is_empty() {
    raise EmptyBatch
  }
  if items.length() > maximum_items {
    raise InvalidLimit
  }
  let mut total_token_count = 0
  let mut trainable_token_count = 0
  for index, item in items {
    if item.policy() != policy {
      raise ForeignPolicy
    }
    if index > 0 {
      let previous = items[index - 1].rollout_id().value()
      let current = item.rollout_id().value()
      if current == previous {
        raise DuplicateRollout
      }
      if current < previous {
        raise NonCanonicalRolloutOrder
      }
    }
    if item.trainable_token_count() >
      maximum_trainable_tokens - trainable_token_count {
      raise TrainableTokenLimitExceeded
    }
    if item.token_count() > maximum_total_tokens - total_token_count {
      raise TotalTokenLimitExceeded
    }
    trainable_token_count += item.trainable_token_count()
    total_token_count += item.token_count()
  }
  {
    id,
    policy,
    items: ReadOnlyArray::from_array(items),
    total_token_count,
    trainable_token_count,
  }
}

///|
pub fn TrainingBatch::id(self : Self) -> TrainingBatchId {
  self.id
}

///|
pub fn TrainingBatch::policy(self : Self) -> @identity.PolicyGeneration {
  self.policy
}

///|
pub fn TrainingBatch::item_count(self : Self) -> Int32 {
  self.items.length()
}

///|
pub fn TrainingBatch::item_at(
  self : Self,
  index : Int32,
) -> TrainingItemRef raise UpdateError {
  if index < 0 || index >= self.items.length() {
    raise InvalidLimit
  }
  self.items[index]
}

///|
pub fn TrainingBatch::total_token_count(self : Self) -> Int32 {
  self.total_token_count
}

///|
pub fn TrainingBatch::trainable_token_count(self : Self) -> Int32 {
  self.trainable_token_count
}
