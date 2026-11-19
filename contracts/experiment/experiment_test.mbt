///|
fn digest(character : Char) -> @identity.Sha256Digest raise {
  let builder = StringBuilder()
  for _ in 0..<64 {
    builder.write_char(character)
  }
  @identity.Sha256Digest::parse(builder.to_string())
}

///|
test "manifest pins every experiment input and exact actor" {
  let actor = @identity.PolicyGeneration::initial(digest('a'))
  let identity = @experiment.ExperimentIdentity::new(digest('b'))
  let dataset = @experiment.DatasetIdentity::new(digest('c'))
  let reward_policy = @experiment.RewardPolicyIdentity::new(digest('d'))
  let tokenizer = @experiment.TokenizerIdentity::new(digest('e'))
  let algorithm = @experiment.AlgorithmIdentity::new(digest('f'), Reinforce)
  let limits = @experiment.ExperimentLimits::new(
    concurrent_groups=@experiment.ConcurrentGroupCapacity::new(8UL),
    rollouts_per_group=@experiment.RolloutsPerGroupCapacity::new(16UL),
    prompt_tokens=@experiment.PromptTokenCapacity::new(4096UL),
    response_tokens=@experiment.ResponseTokenCapacity::new(2048UL),
    pending_updates=@experiment.PendingUpdateCapacity::new(1UL),
  )
  let manifest = @experiment.ExperimentManifest::new(
    identity~,
    actor~,
    dataset~,
    reward_policy~,
    tokenizer~,
    algorithm~,
    limits~,
  )
  assert_eq(manifest.identity(), identity)
  assert_eq(manifest.actor(), actor)
  assert_eq(manifest.dataset(), dataset)
  assert_eq(manifest.reward_policy(), reward_policy)
  assert_eq(manifest.tokenizer(), tokenizer)
  assert_eq(manifest.algorithm(), algorithm)
  assert_eq(manifest.limits(), limits)
}

///|
test "capacity types fail closed at their own bounds" {
  try @experiment.ConcurrentGroupCapacity::new(0UL) catch {
    InvalidCapacity(kind~, value~, maximum~) => {
      assert_eq(kind, ConcurrentGroups)
      assert_eq(value, 0UL)
      assert_eq(maximum, 16UL)
    }
  } noraise {
    _ => fail("zero concurrent capacity must fail")
  }
  try @experiment.RolloutsPerGroupCapacity::new(4097UL) catch {
    InvalidCapacity(kind~, value~, maximum~) => {
      assert_eq(kind, RolloutsPerGroup)
      assert_eq(value, 4097UL)
      assert_eq(maximum, 4096UL)
    }
  } noraise {
    _ => fail("oversized rollout capacity must fail")
  }
  try @experiment.PendingUpdateCapacity::new(2UL) catch {
    InvalidCapacity(kind~, value~, maximum~) => {
      assert_eq(kind, PendingUpdates)
      assert_eq(value, 2UL)
      assert_eq(maximum, 1UL)
    }
  } noraise {
    _ => fail("oversized pending-update capacity must fail")
  }
}
