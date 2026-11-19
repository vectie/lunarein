///|
pub(all) enum CapacityKind {
  ConcurrentGroups
  RolloutsPerGroup
  PromptTokens
  ResponseTokens
  PendingUpdates
} derive(Debug, Eq)

///|
pub(all) suberror ExperimentError {
  InvalidCapacity(kind~ : CapacityKind, value~ : UInt64, maximum~ : UInt64)
} derive(Debug, Eq)

///|
#valtype
pub struct ConcurrentGroupCapacity {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn ConcurrentGroupCapacity::new(
  value : UInt64,
) -> Self raise ExperimentError {
  // Combined with at most 4,096 rollouts per group, this keeps one update at
  // the trainer contract's hard 65,536-item ceiling.
  let maximum = 16UL
  if value == 0UL || value > maximum {
    raise InvalidCapacity(kind=ConcurrentGroups, value~, maximum~)
  }
  { value, }
}

///|
pub fn ConcurrentGroupCapacity::value(self : Self) -> UInt64 {
  self.value
}

///|
#valtype
pub struct RolloutsPerGroupCapacity {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn RolloutsPerGroupCapacity::new(
  value : UInt64,
) -> Self raise ExperimentError {
  let maximum = 4096UL
  if value == 0UL || value > maximum {
    raise InvalidCapacity(kind=RolloutsPerGroup, value~, maximum~)
  }
  { value, }
}

///|
pub fn RolloutsPerGroupCapacity::value(self : Self) -> UInt64 {
  self.value
}

///|
#valtype
pub struct PromptTokenCapacity {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn PromptTokenCapacity::new(value : UInt64) -> Self raise ExperimentError {
  let maximum = 1048576UL
  if value == 0UL || value > maximum {
    raise InvalidCapacity(kind=PromptTokens, value~, maximum~)
  }
  { value, }
}

///|
pub fn PromptTokenCapacity::value(self : Self) -> UInt64 {
  self.value
}

///|
#valtype
pub struct ResponseTokenCapacity {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn ResponseTokenCapacity::new(value : UInt64) -> Self raise ExperimentError {
  let maximum = 1048576UL
  if value == 0UL || value > maximum {
    raise InvalidCapacity(kind=ResponseTokens, value~, maximum~)
  }
  { value, }
}

///|
pub fn ResponseTokenCapacity::value(self : Self) -> UInt64 {
  self.value
}

///|
#valtype
pub struct PendingUpdateCapacity {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn PendingUpdateCapacity::new(value : UInt64) -> Self raise ExperimentError {
  // v1 serializes optimizer/publication ownership. Stale replay is supported,
  // but speculative concurrent generations are intentionally not.
  let maximum = 1UL
  if value == 0UL || value > maximum {
    raise InvalidCapacity(kind=PendingUpdates, value~, maximum~)
  }
  { value, }
}

///|
pub fn PendingUpdateCapacity::value(self : Self) -> UInt64 {
  self.value
}

///|
pub struct ExperimentLimits {
  priv concurrent_groups : ConcurrentGroupCapacity
  priv rollouts_per_group : RolloutsPerGroupCapacity
  priv prompt_tokens : PromptTokenCapacity
  priv response_tokens : ResponseTokenCapacity
  priv pending_updates : PendingUpdateCapacity
} derive(Debug, Eq)

///|
pub fn ExperimentLimits::new(
  concurrent_groups~ : ConcurrentGroupCapacity,
  rollouts_per_group~ : RolloutsPerGroupCapacity,
  prompt_tokens~ : PromptTokenCapacity,
  response_tokens~ : ResponseTokenCapacity,
  pending_updates~ : PendingUpdateCapacity,
) -> Self {
  {
    concurrent_groups,
    rollouts_per_group,
    prompt_tokens,
    response_tokens,
    pending_updates,
  }
}

///|
pub fn ExperimentLimits::concurrent_groups(
  self : Self,
) -> ConcurrentGroupCapacity {
  self.concurrent_groups
}

///|
pub fn ExperimentLimits::rollouts_per_group(
  self : Self,
) -> RolloutsPerGroupCapacity {
  self.rollouts_per_group
}

///|
pub fn ExperimentLimits::prompt_tokens(self : Self) -> PromptTokenCapacity {
  self.prompt_tokens
}

///|
pub fn ExperimentLimits::response_tokens(self : Self) -> ResponseTokenCapacity {
  self.response_tokens
}

///|
pub fn ExperimentLimits::pending_updates(self : Self) -> PendingUpdateCapacity {
  self.pending_updates
}
