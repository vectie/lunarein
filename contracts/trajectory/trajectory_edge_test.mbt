///|
fn edge_policy() -> @identity.PolicyGeneration {
  @identity.PolicyGeneration::initial(
    try! @identity.Sha256Digest::parse("a".repeat(64)),
  )
}

///|
fn expect_trajectory_error(
  action : () -> Unit raise @trajectory.TrajectoryError,
  expected : @trajectory.TrajectoryError,
) -> Unit raise {
  try action() catch {
    error => assert_eq(error, expected)
  } noraise {
    _ => fail("invalid trajectory evidence was accepted")
  }
}

///|
test "token constructors reject invalid vocabulary ids" {
  expect_trajectory_error(
    () => {
      ignore(
        @trajectory.RolloutToken::model(
          token_id=32,
          model_logprob=-1.0,
          sampling_logprob=-1.0,
          maximum_token_id=31,
        ),
      )
    },
    InvalidTokenId(index=0),
  )
  expect_trajectory_error(
    () => {
      ignore(
        @trajectory.RolloutToken::environment(token_id=-1, maximum_token_id=31),
      )
    },
    InvalidTokenId(index=0),
  )
}

///|
test "trajectory enforces limits and exposes immutable evidence" {
  let rollout_id = @identity.RolloutId::new(9UL)
  let group_id = @identity.GroupId::new(4UL)
  let token = @trajectory.RolloutToken::model(
    token_id=7,
    model_logprob=-1.0,
    sampling_logprob=-0.5,
    maximum_token_id=31,
  )
  let trajectory = @trajectory.Trajectory::new(
    rollout_id~,
    group_id~,
    policy=edge_policy(),
    prompt_tokens=[1, 2],
    response_tokens=[token],
    terminal=Completed,
    maximum_prompt_tokens=2,
    maximum_response_tokens=1,
    maximum_token_id=31,
  )
  assert_eq(trajectory.group_id(), group_id)
  assert_eq(trajectory.prompt_length(), 2)
  assert_eq(trajectory.prompt_token_at(1), 2)
  expect_trajectory_error(
    () => ignore(trajectory.prompt_token_at(2)),
    InvalidTokenId(index=2),
  )
  expect_trajectory_error(
    () => ignore(trajectory.response_token_at(1)),
    InvalidTokenId(index=1),
  )
}

///|
test "trajectory rejects invalid dimensions and prompt tokens" {
  let rollout_id = @identity.RolloutId::new(1UL)
  let group_id = @identity.GroupId::new(1UL)
  let policy = edge_policy()
  let token = @trajectory.RolloutToken::environment(
    token_id=7,
    maximum_token_id=31,
  )
  expect_trajectory_error(
    () => {
      ignore(
        @trajectory.Trajectory::new(
          rollout_id~,
          group_id~,
          policy~,
          prompt_tokens=[1],
          response_tokens=[token],
          terminal=Cancelled,
          maximum_prompt_tokens=0,
          maximum_response_tokens=1,
          maximum_token_id=31,
        ),
      )
    },
    InvalidLimit,
  )
  expect_trajectory_error(
    () => {
      ignore(
        @trajectory.Trajectory::new(
          rollout_id~,
          group_id~,
          policy~,
          prompt_tokens=[],
          response_tokens=[],
          terminal=Cancelled,
          maximum_prompt_tokens=1,
          maximum_response_tokens=1,
          maximum_token_id=31,
        ),
      )
    },
    EmptyPrompt,
  )
  expect_trajectory_error(
    () => {
      ignore(
        @trajectory.Trajectory::new(
          rollout_id~,
          group_id~,
          policy~,
          prompt_tokens=[1, 2],
          response_tokens=[],
          terminal=Cancelled,
          maximum_prompt_tokens=1,
          maximum_response_tokens=1,
          maximum_token_id=31,
        ),
      )
    },
    InvalidLimit,
  )
  expect_trajectory_error(
    () => {
      ignore(
        @trajectory.Trajectory::new(
          rollout_id~,
          group_id~,
          policy~,
          prompt_tokens=[32],
          response_tokens=[],
          terminal=Cancelled,
          maximum_prompt_tokens=1,
          maximum_response_tokens=1,
          maximum_token_id=31,
        ),
      )
    },
    InvalidTokenId(index=0),
  )
}
