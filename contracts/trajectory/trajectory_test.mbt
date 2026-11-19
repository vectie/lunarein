///|
fn policy() -> @identity.PolicyGeneration {
  @identity.PolicyGeneration::initial(
    try! @identity.Sha256Digest::parse("a".repeat(64)),
  )
}

///|
test "trajectory preserves token origin and both logprob meanings" {
  let model = @trajectory.RolloutToken::model(
    token_id=7,
    model_logprob=-1.25,
    sampling_logprob=-0.75,
    maximum_token_id=31,
  )
  let environment = @trajectory.RolloutToken::environment(
    token_id=8,
    maximum_token_id=31,
  )
  let trajectory = @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(1UL),
    group_id=try! @identity.GroupId::new(1UL),
    policy=policy(),
    prompt_tokens=[1, 2],
    response_tokens=[model, environment],
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=31,
  )
  assert_eq(trajectory.response_length(), 2)
  assert_true(trajectory.response_token_at(0).is_trainable())
  assert_false(trajectory.response_token_at(1).is_trainable())
  assert_eq(trajectory.response_token_at(0).model_logprob(), Some(-1.25))
  assert_eq(trajectory.response_token_at(0).sampling_logprob(), Some(-0.75))
}

///|
test "trajectory rejects missing completed output and nonfinite evidence" {
  try
    @trajectory.RolloutToken::model(
      token_id=7,
      model_logprob=0.0 / 0.0,
      sampling_logprob=-0.75,
      maximum_token_id=31,
    )
  catch {
    InvalidLogProbability(index=0) => ()
    _ => fail("unexpected logprob error")
  } noraise {
    _ => fail("nonfinite logprob was accepted")
  }
  try
    @trajectory.Trajectory::new(
      rollout_id=try! @identity.RolloutId::new(1UL),
      group_id=try! @identity.GroupId::new(1UL),
      policy=policy(),
      prompt_tokens=[1],
      response_tokens=[],
      terminal=Completed,
      maximum_prompt_tokens=8,
      maximum_response_tokens=8,
      maximum_token_id=31,
    )
  catch {
    EmptyResponse => ()
    _ => fail("unexpected empty-response error")
  } noraise {
    _ => fail("completed empty trajectory was accepted")
  }
}
