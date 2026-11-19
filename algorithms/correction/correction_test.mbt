///|
fn digest(byte : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(byte.repeat(64))
}

///|
fn policies() -> (@identity.PolicyGeneration, @identity.PolicyGeneration) {
  let source = @identity.PolicyGeneration::initial(digest("a"))
  let target = try! @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=digest("b"),
    parent_actor=Some(source.actor()),
  )
  (source, target)
}

///|
fn trajectory(policy : @identity.PolicyGeneration) -> @trajectory.Trajectory {
  let first = try! @trajectory.RolloutToken::model(
    token_id=7,
    model_logprob=-1.0,
    sampling_logprob=-1.1,
    maximum_token_id=31,
  )
  let environment = try! @trajectory.RolloutToken::environment(
    token_id=8,
    maximum_token_id=31,
  )
  let last = try! @trajectory.RolloutToken::model(
    token_id=9,
    model_logprob=-1.0,
    sampling_logprob=-0.9,
    maximum_token_id=31,
  )
  try! @trajectory.Trajectory::new(
    rollout_id=try! @identity.RolloutId::new(1UL),
    group_id=try! @identity.GroupId::new(1UL),
    policy~,
    prompt_tokens=[1, 2],
    response_tokens=[first, environment, last],
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=31,
  )
}

///|
fn staleness(
  source : @identity.PolicyGeneration,
  target : @identity.PolicyGeneration,
) -> @staleness.StalenessEvidence {
  try! @staleness.StalenessPolicy::new(1).evaluate(source~, target~, lineage=[
    source, target,
  ])
}

///|
test "correction is exact and response-token aligned" {
  let (source, target) = policies()
  let item = trajectory(source)
  let scores = @reward.PolicyScoreEvidence::new(item, target_policy=target, logprobs=[
    Some(-0.8),
    None,
    Some(-1.2),
  ])
  let bounds = @correction.ImportanceBounds::new(
    minimum_ratio=0.5,
    maximum_ratio=2.0,
    denominator=BehaviorModel,
  )
  let evidence = @correction.ImportanceCorrectionEvidence::new(
    item,
    staleness(source, target),
    scores,
    bounds,
  )
  assert_eq(evidence.source_policy(), source)
  assert_eq(evidence.target_policy(), target)
  assert_eq(evidence.generations(), 1)
  guard evidence.ratio_at(0) is Some(first) &&
    evidence.ratio_at(2) is Some(last) else {
    fail("model correction ratio is missing")
  }
  assert_true(first > 1.22 && first < 1.23)
  assert_eq(evidence.ratio_at(1), None)
  assert_true(last > 0.81 && last < 0.82)
}

///|
test "sampling-distribution correction is a distinct declared computation" {
  let (source, target) = policies()
  let item = trajectory(source)
  let scores = @reward.PolicyScoreEvidence::new(item, target_policy=target, logprobs=[
    Some(-0.8),
    None,
    Some(-1.2),
  ])
  let bounds = @correction.ImportanceBounds::new(
    minimum_ratio=0.5,
    maximum_ratio=2.0,
    denominator=SamplingDistribution,
  )
  let evidence = @correction.ImportanceCorrectionEvidence::new(
    item,
    staleness(source, target),
    scores,
    bounds,
  )
  assert_eq(evidence.denominator(), SamplingDistribution)
  guard evidence.ratio_at(0) is Some(first) &&
    evidence.ratio_at(2) is Some(last) else {
    fail("sampling correction ratio is missing")
  }
  assert_true(first > 1.34 && first < 1.35)
  assert_true(last > 0.74 && last < 0.75)
}

///|
test "missing, nonfinite, and environment target scores fail closed" {
  let (source, target) = policies()
  let item = trajectory(source)
  try
    @reward.PolicyScoreEvidence::new(item, target_policy=target, logprobs=[
      None,
      None,
      Some(-1.0),
    ])
  catch {
    InconsistentReferenceScore(index=0) => ()
    _ => fail("unexpected missing-score error")
  } noraise {
    _ => fail("missing model score was accepted")
  }
  try
    @reward.PolicyScoreEvidence::new(item, target_policy=target, logprobs=[
      Some(0.0 / 0.0),
      None,
      Some(-1.0),
    ])
  catch {
    InvalidReferenceScore(index=0) => ()
    _ => fail("unexpected nonfinite-score error")
  } noraise {
    _ => fail("nonfinite model score was accepted")
  }
  try
    @reward.PolicyScoreEvidence::new(item, target_policy=target, logprobs=[
      Some(-1.0),
      Some(-1.0),
      Some(-1.0),
    ])
  catch {
    InconsistentReferenceScore(index=1) => ()
    _ => fail("unexpected environment-score error")
  } noraise {
    _ => fail("environment score was accepted")
  }
}

///|
test "unsafe ratios and substituted identities fail closed" {
  let (source, target) = policies()
  let item = trajectory(source)
  let unsafe_scores = @reward.PolicyScoreEvidence::new(
    item,
    target_policy=target,
    logprobs=[Some(0.0), None, Some(-1.0)],
  )
  let tight = @correction.ImportanceBounds::new(
    minimum_ratio=0.9,
    maximum_ratio=1.05,
    denominator=BehaviorModel,
  )
  try
    @correction.ImportanceCorrectionEvidence::new(
      item,
      staleness(source, target),
      unsafe_scores,
      tight,
    )
  catch {
    UnsafeRatio(index=0, ratio=_) => ()
    _ => fail("unexpected unsafe-ratio error")
  } noraise {
    _ => fail("unsafe ratio was accepted")
  }
  let on_policy = try! @staleness.StalenessPolicy::new(0).evaluate(
    source~,
    target=source,
    lineage=[source],
  )
  try
    @correction.ImportanceCorrectionEvidence::new(
      item, on_policy, unsafe_scores, tight,
    )
  catch {
    EvidenceIdentityMismatch => ()
    _ => fail("unexpected identity-mismatch error")
  } noraise {
    _ => fail("substituted target generation was accepted")
  }
}
