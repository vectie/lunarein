///|
fn digest(byte : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(byte.repeat(64))
}

///|
fn trajectory(
  rollout_value : UInt64,
  policy : @identity.PolicyGeneration,
) -> @trajectory.Trajectory {
  let token = try! @trajectory.RolloutToken::model(
    token_id=7,
    model_logprob=-1.25,
    sampling_logprob=-0.75,
    maximum_token_id=31,
  )
  try! @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(rollout_value),
    group_id=try! @identity.GroupId::new(1UL),
    policy~,
    prompt_tokens=[1, 2],
    response_tokens=[token],
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=31,
  )
}

///|
fn advantage(item : @trajectory.Trajectory) -> @advantage.AdvantageEvidence {
  let source = @reward.RewardSourceId::new(digest("f"))
  let scalar = try! @reward.ScalarRewardEvidence::new(item, source~, value=1.0)
  let tokens = try! @reward.TokenRewardEvidence::new(item, source~, values=[0.0])
  try! @advantage.reinforce_returns(
    item,
    scalar,
    tokens,
    discount=1.0,
    algorithm=@experiment.AlgorithmIdentity::new(digest("6"), Reinforce),
  )
}

///|
test "round admits exact advantages and becomes training-ready" {
  let first = @identity.PolicyGeneration::initial(digest("a"))
  let item = trajectory(1UL, first)
  let owner = @round.RoundOwner::new(first, 4)
  owner.admit(item)
  owner.seal_rollouts()
  owner.accept_advantage(advantage(item))
  assert_eq(owner.state(), ReadyForTraining)
  assert_eq(owner.policy(), first)
  assert_eq(owner.rollout_count(), 1)
  assert_eq(owner.advantage_count(), 1)
}

///|
test "round rejects duplicate evidence and supports explicit abort" {
  let first = @identity.PolicyGeneration::initial(digest("a"))
  let item = trajectory(1UL, first)
  let owner = @round.RoundOwner::new(first, 4)
  owner.admit(item)
  try owner.admit(item) catch {
    DuplicateRollout => ()
    _ => fail("unexpected duplicate-rollout error")
  } noraise {
    _ => fail("duplicate rollout was accepted")
  }
  owner.seal_rollouts()
  let evidence = advantage(item)
  owner.accept_advantage(evidence)
  try owner.accept_advantage(evidence) catch {
    InvalidState(expected=AwaitingAdvantages, actual=ReadyForTraining) => ()
    _ => fail("unexpected post-ready error")
  } noraise {
    _ => fail("evidence was accepted after readiness")
  }
  owner.abort(OperatorRequested)
  assert_eq(owner.state(), RoundAborted)
  assert_eq(owner.abort_reason(), Some(OperatorRequested))
}
