///|
fn digest(fill : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(fill.repeat(64))
}

///|
fn source() -> @reward.RewardSourceId {
  @reward.RewardSourceId::new(digest("d"))
}

///|
fn algorithm(kind : @experiment.AlgorithmKind) -> @experiment.AlgorithmIdentity {
  @experiment.AlgorithmIdentity::new(digest("6"), kind)
}

///|
fn trajectory(
  rollout : UInt64,
  group : UInt64,
  first_logprob : Double,
) -> @trajectory.Trajectory {
  let response = [
    try! @trajectory.RolloutToken::model(
      token_id=10,
      model_logprob=first_logprob,
      sampling_logprob=first_logprob,
      maximum_token_id=100,
    ),
    try! @trajectory.RolloutToken::environment(
      token_id=11,
      maximum_token_id=100,
    ),
    try! @trajectory.RolloutToken::model(
      token_id=12,
      model_logprob=-0.3,
      sampling_logprob=-0.3,
      maximum_token_id=100,
    ),
  ]
  try! @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(rollout),
    group_id=try! @identity.GroupId::new(group),
    policy=@identity.PolicyGeneration::initial(digest("a")),
    prompt_tokens=[1],
    response_tokens=response,
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=100,
  )
}

///|
fn rewards(
  trajectory : @trajectory.Trajectory,
  scalar_value : Double,
) -> (@reward.ScalarRewardEvidence, @reward.TokenRewardEvidence) {
  (
    try! @reward.ScalarRewardEvidence::new(
      trajectory,
      source=source(),
      value=scalar_value,
    ),
    try! @reward.TokenRewardEvidence::new(trajectory, source=source(), values=[
      1.0, 2.0, 3.0,
    ]),
  )
}

///|
fn environment_only_trajectory() -> @trajectory.Trajectory {
  let response = [
    try! @trajectory.RolloutToken::environment(
      token_id=11,
      maximum_token_id=100,
    ),
  ]
  try! @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(9),
    group_id=try! @identity.GroupId::new(9),
    policy=@identity.PolicyGeneration::initial(digest("a")),
    prompt_tokens=[1],
    response_tokens=response,
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=100,
  )
}

///|
test "reinforce reward-to-go crosses environment events but masks them" {
  let trajectory = trajectory(1, 1, -0.2)
  let (scalar, token) = rewards(trajectory, 4.0)
  let result = @advantage.reinforce_returns(
    trajectory,
    scalar,
    token,
    discount=1.0,
    algorithm=algorithm(Reinforce),
  )
  assert_eq(result.rollout_id(), trajectory.rollout_id())
  assert_eq(result.policy(), trajectory.policy())
  assert_eq(result.value_at(0), 10.0)
  assert_eq(result.value_at(1), 0.0)
  assert_eq(result.value_at(2), 7.0)
  assert_eq(result.trainable_token_count(), 2)
}

///|
test "reference KL uses actor model probability explicitly" {
  let trajectory = trajectory(1, 1, -0.2)
  let (scalar, token) = rewards(trajectory, 4.0)
  let reference = @reward.ReferenceScoreEvidence::new(
    trajectory,
    reference_actor=digest("b"),
    logprobs=[Some(-0.5), None, Some(-0.7)],
  )
  let result = @advantage.reinforce_returns_with_reference_kl(
    trajectory,
    scalar,
    token,
    reference,
    discount=1.0,
    kl_coefficient=2.0,
    algorithm=algorithm(ReinforceReferenceKl),
  )
  assert_eq(result.value_at(0), 8.6)
  assert_eq(result.value_at(1), 0.0)
  assert_eq(result.value_at(2), 6.2)
}

///|
test "GRPO normalization is deterministic and masks environment tokens" {
  let first = trajectory(1, 5, -0.2)
  let second = trajectory(2, 5, -0.2)
  let first_reward = try! @reward.ScalarRewardEvidence::new(
    first,
    source=source(),
    value=1.0,
  )
  let second_reward = try! @reward.ScalarRewardEvidence::new(
    second,
    source=source(),
    value=3.0,
  )
  let outputs = @advantage.grpo_group_normalize(
    [first, second],
    [first_reward, second_reward],
    minimum_variance=0.000001,
    algorithm=algorithm(Grpo),
  )
  assert_eq(outputs.length(), 2)
  assert_eq(outputs[0].value_at(0), -1.0)
  assert_eq(outputs[0].value_at(1), 0.0)
  assert_eq(outputs[1].value_at(2), 1.0)
}

///|
test "GRPO rejects degenerate and duplicate groups" {
  let first = trajectory(1, 5, -0.2)
  let duplicate = trajectory(1, 5, -0.2)
  let first_reward = try! @reward.ScalarRewardEvidence::new(
    first,
    source=source(),
    value=1.0,
  )
  let duplicate_reward = try! @reward.ScalarRewardEvidence::new(
    duplicate,
    source=source(),
    value=2.0,
  )
  try
    @advantage.grpo_group_normalize(
      [first, duplicate],
      [first_reward, duplicate_reward],
      minimum_variance=0.000001,
      algorithm=algorithm(Grpo),
    )
  catch {
    DuplicateRollout => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected duplicate rejection")
  }
  let second = trajectory(2, 5, -0.2)
  let second_reward = try! @reward.ScalarRewardEvidence::new(
    second,
    source=source(),
    value=1.0,
  )
  try
    @advantage.grpo_group_normalize(
      [first, second],
      [first_reward, second_reward],
      minimum_variance=0.000001,
      algorithm=algorithm(Grpo),
    )
  catch {
    DegenerateGroup => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected variance rejection")
  }
}

///|
test "GAE produces aligned PPO targets" {
  let trajectory = trajectory(1, 1, -0.2)
  let (scalar, token) = rewards(trajectory, 4.0)
  let values = @advantage.StateValueEvidence::new(trajectory, values=[
    0.5, 1.0, 1.5, 0.0,
  ])
  let result = @advantage.gae_ppo_targets(
    trajectory,
    scalar,
    token,
    values,
    discount=1.0,
    trace_decay=1.0,
    algorithm=algorithm(GaePpo),
  )
  assert_eq(result.advantage_at(0), 9.5)
  assert_eq(result.value_return_at(0), 10.0)
  assert_eq(result.advantage_at(1), 0.0)
  assert_eq(result.value_return_at(1), 0.0)
  assert_eq(result.advantage_at(2), 5.5)
  assert_eq(result.value_return_at(2), 7.0)
}

///|
test "construction rejects substituted evidence and reward sources" {
  let first = trajectory(1, 1, -0.2)
  let second = trajectory(2, 1, -0.2)
  let (first_scalar, first_token) = rewards(first, 1.0)
  let (second_scalar, _) = rewards(second, 1.0)
  try
    @advantage.reinforce_returns(
      first,
      second_scalar,
      first_token,
      discount=1.0,
      algorithm=algorithm(Reinforce),
    )
  catch {
    EvidenceIdentityMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected identity rejection")
  }
  let other_source = @reward.RewardSourceId::new(digest("e"))
  let mismatched_token = @reward.TokenRewardEvidence::new(
    first,
    source=other_source,
    values=[1.0, 2.0, 3.0],
  )
  try
    @advantage.reinforce_returns(
      first,
      first_scalar,
      mismatched_token,
      discount=1.0,
      algorithm=algorithm(Reinforce),
    )
  catch {
    RewardSourceMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected source rejection")
  }
}

///|
test "state values reject invalid bootstrap and GAE rejects substitution" {
  let first = trajectory(1, 1, -0.2)
  try
    @advantage.StateValueEvidence::new(first, values=[0.0, 0.0, 0.0, 1.0])
  catch {
    InvalidTerminalBootstrap => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected bootstrap rejection")
  }
  try
    @advantage.StateValueEvidence::new(first, values=[0.0, 0.0 / 0.0, 0.0, 0.0])
  catch {
    NonFiniteValue(index=1) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected nonfinite value rejection")
  }
  let second = trajectory(2, 1, -0.2)
  let (scalar, token) = rewards(first, 1.0)
  let second_values = @advantage.StateValueEvidence::new(second, values=[
    0.0, 0.0, 0.0, 0.0,
  ])
  try
    @advantage.gae_ppo_targets(
      first,
      scalar,
      token,
      second_values,
      discount=1.0,
      trace_decay=1.0,
      algorithm=algorithm(GaePpo),
    )
  catch {
    EvidenceIdentityMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected value identity rejection")
  }
}

///|
test "algorithms reject invalid numeric parameters" {
  let trajectory = trajectory(1, 1, -0.2)
  let (scalar, token) = rewards(trajectory, 1.0)
  try
    @advantage.reinforce_returns(
      trajectory,
      scalar,
      token,
      discount=1.1,
      algorithm=algorithm(Reinforce),
    )
  catch {
    InvalidDiscount => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected discount rejection")
  }
  let reference = @reward.ReferenceScoreEvidence::new(
    trajectory,
    reference_actor=digest("b"),
    logprobs=[Some(-0.5), None, Some(-0.7)],
  )
  try
    @advantage.reinforce_returns_with_reference_kl(
      trajectory,
      scalar,
      token,
      reference,
      discount=1.0,
      kl_coefficient=-0.1,
      algorithm=algorithm(ReinforceReferenceKl),
    )
  catch {
    InvalidKlCoefficient => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected KL coefficient rejection")
  }
}

///|
test "algorithm kind cannot be relabelled by a caller digest" {
  let trajectory = trajectory(1, 1, -0.2)
  let (scalar, token) = rewards(trajectory, 1.0)
  try
    @advantage.reinforce_returns(
      trajectory,
      scalar,
      token,
      discount=1.0,
      algorithm=algorithm(GaePpo),
    )
  catch {
    AlgorithmMismatch => ()
    _ => fail("unexpected algorithm-kind error")
  } noraise {
    _ => fail("REINFORCE accepted a GAE/PPO identity")
  }
}

///|
test "reference substitution and trajectories without model actions fail closed" {
  let first = trajectory(1, 1, -0.2)
  let second = trajectory(2, 1, -0.2)
  let (scalar, token) = rewards(first, 1.0)
  let substituted_reference = @reward.ReferenceScoreEvidence::new(
    second,
    reference_actor=digest("b"),
    logprobs=[Some(-0.5), None, Some(-0.7)],
  )
  try
    @advantage.reinforce_returns_with_reference_kl(
      first,
      scalar,
      token,
      substituted_reference,
      discount=1.0,
      kl_coefficient=0.1,
      algorithm=algorithm(ReinforceReferenceKl),
    )
  catch {
    EvidenceIdentityMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected reference identity rejection")
  }
  let environment_only = environment_only_trajectory()
  let environment_scalar = @reward.ScalarRewardEvidence::new(
    environment_only,
    source=source(),
    value=1.0,
  )
  let environment_token = @reward.TokenRewardEvidence::new(
    environment_only,
    source=source(),
    values=[1.0],
  )
  try
    @advantage.reinforce_returns(
      environment_only,
      environment_scalar,
      environment_token,
      discount=1.0,
      algorithm=algorithm(Reinforce),
    )
  catch {
    NoTrainableTokens => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected no-trainable-token rejection")
  }
}

///|
test "GRPO rejects mixed groups and reward definitions" {
  let first = trajectory(1, 5, -0.2)
  let other_group = trajectory(2, 6, -0.2)
  let first_reward = @reward.ScalarRewardEvidence::new(
    first,
    source=source(),
    value=1.0,
  )
  let other_group_reward = @reward.ScalarRewardEvidence::new(
    other_group,
    source=source(),
    value=2.0,
  )
  try
    @advantage.grpo_group_normalize(
      [first, other_group],
      [first_reward, other_group_reward],
      minimum_variance=0.000001,
      algorithm=algorithm(Grpo),
    )
  catch {
    MixedGroup => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected group rejection")
  }
  let same_group = trajectory(2, 5, -0.2)
  let other_source = @reward.RewardSourceId::new(digest("e"))
  let other_source_reward = @reward.ScalarRewardEvidence::new(
    same_group,
    source=other_source,
    value=2.0,
  )
  try
    @advantage.grpo_group_normalize(
      [first, same_group],
      [first_reward, other_source_reward],
      minimum_variance=0.000001,
      algorithm=algorithm(Grpo),
    )
  catch {
    MixedRewardSource => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected reward-source rejection")
  }
}
