///|
fn invariant_policy() -> @identity.PolicyGeneration {
  @identity.PolicyGeneration::initial(
    try! @identity.Sha256Digest::parse("a".repeat(64)),
  )
}

///|
fn construct_with_token(
  token : RolloutToken,
) -> Trajectory raise TrajectoryError {
  Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(1UL),
    group_id=try! @identity.GroupId::new(1UL),
    policy=invariant_policy(),
    prompt_tokens=[1],
    response_tokens=[token],
    terminal=Completed,
    maximum_prompt_tokens=1,
    maximum_response_tokens=1,
    maximum_token_id=31,
  )
}

///|
test "trajectory defends invariants even inside the owning package" {
  let invalid_id : RolloutToken = {
    token_id: 32,
    origin: ModelGenerated,
    model_logprob: Some(-1.0),
    sampling_logprob: Some(-1.0),
  }
  try construct_with_token(invalid_id) catch {
    InvalidTokenId(index=0) => ()
    _ => fail("unexpected invalid-token error")
  } noraise {
    _ => fail("invalid private token was accepted")
  }
  let missing_model : RolloutToken = {
    token_id: 7,
    origin: ModelGenerated,
    model_logprob: None,
    sampling_logprob: Some(-1.0),
  }
  try construct_with_token(missing_model) catch {
    InconsistentTokenEvidence(index=0) => ()
    _ => fail("unexpected missing-model error")
  } noraise {
    _ => fail("model token without evidence was accepted")
  }
  let polluted_environment : RolloutToken = {
    token_id: 7,
    origin: EnvironmentSupplied,
    model_logprob: Some(-1.0),
    sampling_logprob: None,
  }
  try construct_with_token(polluted_environment) catch {
    InconsistentTokenEvidence(index=0) => ()
    _ => fail("unexpected environment-evidence error")
  } noraise {
    _ => fail("environment token with model evidence was accepted")
  }
}
