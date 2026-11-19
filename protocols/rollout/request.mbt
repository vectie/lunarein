///|
/// Per-request capacities are immutable evidence, not a global configuration
/// surface. The v1 protocol admits at most 4,096 rollout slots, 1,048,576
/// prompt tokens, 1,048,576 response tokens per slot, and token IDs through
/// 2,147,483,647. Adapters must reject evidence outside these hard ceilings.
pub struct RolloutLimits {
  priv maximum_rollouts : Int32
  priv maximum_prompt_tokens : Int32
  priv maximum_response_tokens : Int32
  priv maximum_token_id : Int32
} derive(Debug, Eq)

///|
pub fn RolloutLimits::new(
  maximum_rollouts~ : Int32,
  maximum_prompt_tokens~ : Int32,
  maximum_response_tokens~ : Int32,
  maximum_token_id~ : Int32,
) -> Self raise RolloutProtocolError {
  if maximum_rollouts <= 0 ||
    maximum_rollouts > 4096 ||
    maximum_prompt_tokens <= 0 ||
    maximum_prompt_tokens > 1048576 ||
    maximum_response_tokens <= 0 ||
    maximum_response_tokens > 1048576 ||
    maximum_token_id < 0 ||
    maximum_token_id > 2147483647 {
    raise InvalidLimit
  }
  {
    maximum_rollouts,
    maximum_prompt_tokens,
    maximum_response_tokens,
    maximum_token_id,
  }
}

///|
pub fn RolloutLimits::maximum_rollouts(self : Self) -> Int32 {
  self.maximum_rollouts
}

///|
pub fn RolloutLimits::maximum_prompt_tokens(self : Self) -> Int32 {
  self.maximum_prompt_tokens
}

///|
pub fn RolloutLimits::maximum_response_tokens(self : Self) -> Int32 {
  self.maximum_response_tokens
}

///|
pub fn RolloutLimits::maximum_token_id(self : Self) -> Int32 {
  self.maximum_token_id
}

///|
/// Minimum usable terminal trajectories required from an oversampled group.
pub struct RolloutSelectionPolicy {
  priv minimum_usable : Int32
} derive(Debug, Eq)

///|
pub fn RolloutSelectionPolicy::new(
  minimum_usable : Int32,
) -> Self raise RolloutProtocolError {
  if minimum_usable <= 0 || minimum_usable > 4096 {
    raise InvalidSelectionPolicy
  }
  { minimum_usable, }
}

///|
pub fn RolloutSelectionPolicy::minimum_usable(self : Self) -> Int32 {
  self.minimum_usable
}

///|
/// One deterministic rollout slot within a prompt group.
pub struct RolloutSlot {
  priv rollout_id : @identity.RolloutId
  priv sampling : SamplingIdentity
} derive(Debug, Eq)

///|
pub fn RolloutSlot::new(
  rollout_id~ : @identity.RolloutId,
  sampling~ : SamplingIdentity,
) -> Self {
  { rollout_id, sampling, }
}

///|
pub fn RolloutSlot::rollout_id(self : Self) -> @identity.RolloutId {
  self.rollout_id
}

///|
pub fn RolloutSlot::sampling(self : Self) -> SamplingIdentity {
  self.sampling
}

///|
/// Immutable evidence requesting exactly N deterministic rollout slots for one
/// prompt group and actor generation.
pub struct RolloutGroupRequest {
  priv protocol_version : @version.ProtocolVersion
  priv request_id : RolloutRequestId
  priv experiment : @experiment.ExperimentIdentity
  priv dataset : @experiment.DatasetIdentity
  priv group_id : @identity.GroupId
  priv actor : @identity.PolicyGeneration
  priv tokenizer : @experiment.TokenizerIdentity
  priv limits : RolloutLimits
  priv selection : RolloutSelectionPolicy
  priv prompt_tokens : ReadOnlyArray[Int32]
  priv slots : ReadOnlyArray[RolloutSlot]
}

///|
pub fn RolloutGroupRequest::new(
  protocol_version~ : @version.ProtocolVersion,
  request_id~ : RolloutRequestId,
  experiment~ : @experiment.ExperimentIdentity,
  dataset~ : @experiment.DatasetIdentity,
  group_id~ : @identity.GroupId,
  actor~ : @identity.PolicyGeneration,
  tokenizer~ : @experiment.TokenizerIdentity,
  limits~ : RolloutLimits,
  selection~ : RolloutSelectionPolicy,
  prompt_tokens~ : ArrayView[Int32],
  slots~ : ArrayView[RolloutSlot],
) -> Self raise RolloutProtocolError {
  require_supported_version(protocol_version)
  if prompt_tokens.is_empty() {
    raise EmptyPrompt
  }
  if prompt_tokens.length() > limits.maximum_prompt_tokens() {
    raise InvalidLimit
  }
  for index, token_id in prompt_tokens {
    if token_id < 0 || token_id > limits.maximum_token_id() {
      raise InvalidPromptToken(index~)
    }
  }
  if slots.is_empty() {
    raise EmptyRolloutSlots
  }
  if slots.length() > limits.maximum_rollouts() {
    raise TooManyRolloutSlots
  }
  if selection.minimum_usable() > slots.length() {
    raise InvalidSelectionPolicy
  }
  for index in 0..<slots.length() {
    for previous in 0..<index {
      if slots[index].rollout_id() == slots[previous].rollout_id() {
        raise DuplicateRolloutId(index~)
      }
      if slots[index].sampling() == slots[previous].sampling() {
        raise DuplicateSamplingIdentity(index~)
      }
    }
  }
  {
    protocol_version,
    request_id,
    experiment,
    dataset,
    group_id,
    actor,
    tokenizer,
    limits,
    selection,
    prompt_tokens: ReadOnlyArray::from_array(prompt_tokens),
    slots: ReadOnlyArray::from_array(slots),
  }
}

///|
pub fn RolloutGroupRequest::protocol_version(
  self : Self,
) -> @version.ProtocolVersion {
  self.protocol_version
}

///|
pub fn RolloutGroupRequest::request_id(self : Self) -> RolloutRequestId {
  self.request_id
}

///|
pub fn RolloutGroupRequest::experiment(
  self : Self,
) -> @experiment.ExperimentIdentity {
  self.experiment
}

///|
pub fn RolloutGroupRequest::dataset(self : Self) -> @experiment.DatasetIdentity {
  self.dataset
}

///|
pub fn RolloutGroupRequest::group_id(self : Self) -> @identity.GroupId {
  self.group_id
}

///|
pub fn RolloutGroupRequest::actor(self : Self) -> @identity.PolicyGeneration {
  self.actor
}

///|
pub fn RolloutGroupRequest::tokenizer(
  self : Self,
) -> @experiment.TokenizerIdentity {
  self.tokenizer
}

///|
pub fn RolloutGroupRequest::limits(self : Self) -> RolloutLimits {
  self.limits
}

///|
pub fn RolloutGroupRequest::selection(self : Self) -> RolloutSelectionPolicy {
  self.selection
}

///|
pub fn RolloutGroupRequest::prompt_length(self : Self) -> Int32 {
  self.prompt_tokens.length()
}

///|
pub fn RolloutGroupRequest::prompt_token_at(
  self : Self,
  index : Int32,
) -> Int32 raise RolloutProtocolError {
  if index < 0 || index >= self.prompt_tokens.length() {
    raise InvalidPromptToken(index~)
  }
  self.prompt_tokens[index]
}

///|
pub fn RolloutGroupRequest::rollout_count(self : Self) -> Int32 {
  self.slots.length()
}

///|
pub fn RolloutGroupRequest::slot_at(
  self : Self,
  index : Int32,
) -> RolloutSlot raise RolloutProtocolError {
  if index < 0 || index >= self.slots.length() {
    raise InvalidSlotIndex(index~)
  }
  self.slots[index]
}

///|
fn RolloutGroupRequest::slot_for_rollout(
  self : Self,
  rollout_id : @identity.RolloutId,
) -> RolloutSlot? {
  for slot in self.slots {
    if slot.rollout_id() == rollout_id {
      return Some(slot)
    }
  }
  None
}

///|
pub fn RolloutGroupRequest::slot_index_for_rollout(
  self : Self,
  rollout_id : @identity.RolloutId,
) -> Int32? {
  for index, slot in self.slots {
    if slot.rollout_id() == rollout_id {
      return Some(index)
    }
  }
  None
}
