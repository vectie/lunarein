///|
test "round rejects empty and exhausted capacity without mutation" {
  let policy = @identity.PolicyGeneration::initial(digest("a"))
  try @round.RoundOwner::new(policy, 0) catch {
    InvalidCapacity => ()
    _ => fail("unexpected capacity error")
  } noraise {
    _ => fail("zero round capacity was accepted")
  }
  let owner = @round.RoundOwner::new(policy, 1)
  try owner.seal_rollouts() catch {
    EmptyRound => ()
    _ => fail("unexpected empty-round error")
  } noraise {
    _ => fail("empty round was sealed")
  }
  owner.admit(trajectory(1UL, policy))
  try owner.admit(trajectory(2UL, policy)) catch {
    InvalidCapacity => ()
    _ => fail("unexpected exhausted-capacity error")
  } noraise {
    _ => fail("rollout exceeded fixed capacity")
  }
  assert_eq(owner.rollout_count(), 1)
}

///|
test "round rejects foreign, unknown, and duplicate advantage evidence" {
  let policy = @identity.PolicyGeneration::initial(digest("a"))
  let foreign = @identity.PolicyGeneration::initial(digest("b"))
  let owner = @round.RoundOwner::new(policy, 3)
  try owner.admit(trajectory(1UL, foreign)) catch {
    ForeignPolicy => ()
    _ => fail("unexpected foreign-policy error")
  } noraise {
    _ => fail("foreign rollout was admitted")
  }
  let first = trajectory(1UL, policy)
  let second = trajectory(2UL, policy)
  owner.admit(first)
  owner.admit(second)
  owner.seal_rollouts()
  try owner.accept_advantage(advantage(trajectory(3UL, policy))) catch {
    UnknownRollout => ()
    _ => fail("unexpected unknown-rollout error")
  } noraise {
    _ => fail("unknown rollout advantage was admitted")
  }
  let first_advantage = advantage(first)
  owner.accept_advantage(first_advantage)
  try owner.accept_advantage(first_advantage) catch {
    DuplicateAdvantage => ()
    _ => fail("unexpected duplicate-advantage error")
  } noraise {
    _ => fail("duplicate advantage was admitted")
  }
  assert_eq(owner.advantage_count(), 1)
  assert_eq(owner.state(), AwaitingAdvantages)
}

///|
test "round detects same-id same-shape content substitution" {
  let policy = @identity.PolicyGeneration::initial(digest("a"))
  let original = trajectory(1UL, policy)
  let owner = @round.RoundOwner::new(policy, 1)
  owner.admit(original)
  owner.seal_rollouts()
  let model = @trajectory.RolloutToken::model(
    token_id=8,
    model_logprob=-1.0,
    sampling_logprob=-1.0,
    maximum_token_id=31,
  )
  let substituted = @trajectory.Trajectory::new(
    rollout_id=original.rollout_id(),
    group_id=original.group_id(),
    policy~,
    prompt_tokens=[1, 2],
    response_tokens=[model],
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=31,
  )
  let source = @reward.RewardSourceId::new(digest("f"))
  let scalar = @reward.ScalarRewardEvidence::new(
    substituted,
    source~,
    value=1.0,
  )
  let tokens = @reward.TokenRewardEvidence::new(substituted, source~, values=[
    0.0,
  ])
  let substituted_advantage = @advantage.reinforce_returns(
    substituted,
    scalar,
    tokens,
    discount=1.0,
    algorithm=@experiment.AlgorithmIdentity::new(digest("6"), Reinforce),
  )
  try owner.accept_advantage(substituted_advantage) catch {
    EvidenceShapeMismatch => ()
    _ => fail("unexpected evidence-identity error")
  } noraise {
    _ => fail("same-id same-shape substituted content was accepted")
  }
  assert_eq(owner.advantage_count(), 0)
}

///|
test "round abort is terminal and retains reason" {
  let policy = @identity.PolicyGeneration::initial(digest("a"))
  let owner = @round.RoundOwner::new(policy, 1)
  owner.abort(TrainerFailure)
  assert_eq(owner.abort_reason(), Some(TrainerFailure))
  try owner.abort(OperatorRequested) catch {
    InvalidState(expected=CollectingRollouts, actual=RoundAborted) => ()
    _ => fail("unexpected repeated-abort error")
  } noraise {
    _ => fail("aborted round was aborted again")
  }
}
