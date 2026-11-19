///|
fn digest(fill : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(fill.repeat(64))
}

///|
fn policy() -> @identity.PolicyGeneration {
  @identity.PolicyGeneration::initial(digest("a"))
}

///|
fn mixed_trajectory() -> @trajectory.Trajectory {
  let response = [
    try! @trajectory.RolloutToken::model(
      token_id=10,
      model_logprob=-0.2,
      sampling_logprob=-0.3,
      maximum_token_id=100,
    ),
    try! @trajectory.RolloutToken::environment(
      token_id=11,
      maximum_token_id=100,
    ),
  ]
  try! @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(1),
    group_id=try! @identity.GroupId::new(1),
    policy=policy(),
    prompt_tokens=[1],
    response_tokens=response,
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=100,
  )
}

///|
test "scalar and token rewards retain exact identity" {
  let trajectory = mixed_trajectory()
  let source = @reward.RewardSourceId::new(digest("b"))
  let scalar = @reward.ScalarRewardEvidence::new(trajectory, source~, value=3.5)
  let token = @reward.TokenRewardEvidence::new(trajectory, source~, values=[
    0.25, 1.0,
  ])
  assert_eq(scalar.rollout_id(), trajectory.rollout_id())
  assert_eq(scalar.policy(), trajectory.policy())
  assert_eq(scalar.source(), source)
  assert_eq(scalar.value(), 3.5)
  assert_eq(token.value_at(1), 1.0)
}

///|
test "reference scores follow token origin" {
  let trajectory = mixed_trajectory()
  let scores = @reward.ReferenceScoreEvidence::new(
    trajectory,
    reference_actor=digest("c"),
    logprobs=[Some(-0.4), None],
  )
  assert_eq(scores.rollout_id(), trajectory.rollout_id())
  assert_eq(scores.policy(), trajectory.policy())
  assert_eq(scores.logprob_at(0), Some(-0.4))
  assert_eq(scores.logprob_at(1), None)
}

///|
test "misaligned and inconsistent evidence fails closed" {
  let trajectory = mixed_trajectory()
  let source = @reward.RewardSourceId::new(digest("b"))
  try
    @reward.TokenRewardEvidence::new(trajectory, source~, values=[1.0])
  catch {
    TokenRewardLengthMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected misalignment")
  }
  try
    @reward.ReferenceScoreEvidence::new(
      trajectory,
      reference_actor=digest("c"),
      logprobs=[Some(-0.4), Some(-0.5)],
    )
  catch {
    InconsistentReferenceScore(index=1) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected origin mismatch")
  }
}

///|
test "reward constructors reject nonfinite and ineligible evidence" {
  let trajectory = mixed_trajectory()
  let source = @reward.RewardSourceId::new(digest("b"))
  try
    @reward.ScalarRewardEvidence::new(trajectory, source~, value=0.0 / 0.0)
  catch {
    NonFiniteScalarReward => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected nonfinite scalar rejection")
  }
  try
    @reward.TokenRewardEvidence::new(trajectory, source~, values=[
      0.0,
      1.0 / 0.0,
    ])
  catch {
    NonFiniteTokenReward(index=1) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected nonfinite token rejection")
  }
  try
    @reward.ReferenceScoreEvidence::new(
      trajectory,
      reference_actor=digest("c"),
      logprobs=[Some(0.1), None],
    )
  catch {
    InvalidReferenceScore(index=0) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected invalid reference score rejection")
  }
  let cancelled = @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(2),
    group_id=try! @identity.GroupId::new(1),
    policy=policy(),
    prompt_tokens=[1],
    response_tokens=[],
    terminal=Cancelled,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=100,
  )
  try @reward.ScalarRewardEvidence::new(cancelled, source~, value=1.0) catch {
    IneligibleTerminal => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected terminal rejection")
  }
}
