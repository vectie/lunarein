///|
/// Bounded ownership for all prompt groups participating in one optimizer
/// update. Rollout IDs are unique across the whole update, and every requested
/// slot must produce one terminal response before group selection can seal.
priv struct CycleGroups {
  requests : FixedArray[@rollout.RolloutGroupRequest?]
  group_terminal_counts : FixedArray[Int32]
  group_usable_counts : FixedArray[Int32]
  requested_rollout_keys : FixedArray[UInt64]
  terminal_rollout_keys : FixedArray[UInt64]
  mut group_count : Int32
  mut terminal_count : Int32
  mut usable_count : Int32
}

///|
fn CycleGroups::new(
  maximum_groups : Int32,
  maximum_total_rollouts : Int32,
) -> Self raise CycleError {
  if maximum_groups <= 0 ||
    maximum_total_rollouts <= 0 ||
    maximum_total_rollouts > 65536 {
    raise ExperimentLimitExceeded
  }
  let mut table_capacity = 2
  while table_capacity < maximum_total_rollouts * 2 {
    table_capacity *= 2
  }
  {
    requests: FixedArray::make(maximum_groups, None),
    group_terminal_counts: FixedArray::make(maximum_groups, 0),
    group_usable_counts: FixedArray::make(maximum_groups, 0),
    requested_rollout_keys: FixedArray::make(table_capacity, 0UL),
    terminal_rollout_keys: FixedArray::make(table_capacity, 0UL),
    group_count: 0,
    terminal_count: 0,
    usable_count: 0,
  }
}

///|
fn lookup_key(keys : FixedArray[UInt64], key : UInt64) -> Int32 {
  let mixed = key ^ (key >> 33) ^ (key >> 17)
  let start = (mixed % keys.length().to_uint64()).to_int()
  for probe in 0..<keys.length() {
    let index = (start + probe) % keys.length()
    if keys[index] == 0UL || keys[index] == key {
      return index
    }
  }
  -1
}

///|
fn contains_key(keys : FixedArray[UInt64], key : UInt64) -> Bool {
  let index = lookup_key(keys, key)
  index >= 0 && keys[index] == key
}

///|
fn insert_key(keys : FixedArray[UInt64], key : UInt64) -> Unit raise CycleError {
  let index = lookup_key(keys, key)
  if index < 0 || keys[index] != 0UL {
    raise DuplicateGroupRollout
  }
  keys[index] = key
}

///|
fn CycleGroups::add(
  self : Self,
  request : @rollout.RolloutGroupRequest,
) -> Unit raise CycleError {
  if self.group_count >= self.requests.length() {
    raise ExperimentLimitExceeded
  }
  for index in 0..<self.group_count {
    guard self.requests[index] is Some(existing) else { raise RequestMismatch }
    if existing.request_id() == request.request_id() ||
      existing.group_id() == request.group_id() {
      raise DuplicateGroup
    }
  }
  for slot_index in 0..<request.rollout_count() {
    let slot = request.slot_at(slot_index) catch { _ => raise RequestMismatch }
    if contains_key(self.requested_rollout_keys, slot.rollout_id().value()) {
      raise DuplicateGroupRollout
    }
  }
  for slot_index in 0..<request.rollout_count() {
    let slot = request.slot_at(slot_index) catch { _ => raise RequestMismatch }
    insert_key(self.requested_rollout_keys, slot.rollout_id().value())
  }
  self.requests[self.group_count] = Some(request)
  self.group_count += 1
}

///|
fn CycleGroups::group_for_response(
  self : Self,
  response : @rollout.RolloutResponse,
) -> Int32 {
  for index in 0..<self.group_count {
    match self.requests[index] {
      Some(request) => if response.matches_request(request) { return index }
      None => ()
    }
  }
  -1
}

///|
fn CycleGroups::record(
  self : Self,
  response : @rollout.RolloutResponse,
) -> Bool raise CycleError {
  let group_index = self.group_for_response(response)
  if group_index < 0 {
    raise RequestMismatch
  }
  let rollout_id = response.trajectory().rollout_id().value()
  if contains_key(self.terminal_rollout_keys, rollout_id) {
    raise DuplicateRolloutResponse
  }
  if self.terminal_count >= self.requested_rollout_keys.length() / 2 {
    raise ExperimentLimitExceeded
  }
  let usable = match response.terminal() {
    Complete | Partial(_) => true
    Cancelled(_) | Failed(_) => false
  }
  let terminal_index = lookup_key(self.terminal_rollout_keys, rollout_id)
  if terminal_index < 0 {
    raise ExperimentLimitExceeded
  }
  self.terminal_rollout_keys[terminal_index] = rollout_id
  self.terminal_count += 1
  self.group_terminal_counts[group_index] += 1
  if usable {
    self.group_usable_counts[group_index] += 1
    self.usable_count += 1
  }
  usable
}

///|
fn CycleGroups::require_sealable(self : Self) -> Unit raise CycleError {
  if self.group_count == 0 {
    raise IncompleteRolloutSet
  }
  for index in 0..<self.group_count {
    guard self.requests[index] is Some(request) else { raise RequestMismatch }
    if self.group_terminal_counts[index] != request.rollout_count() {
      raise IncompleteRolloutSet
    }
    if self.group_usable_counts[index] < request.selection().minimum_usable() {
      raise InsufficientUsableRollouts
    }
  }
}

///|
fn CycleGroups::group_count(self : Self) -> Int32 {
  self.group_count
}
