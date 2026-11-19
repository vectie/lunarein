///|
fn test_digest(character : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(character.repeat(64))
}

///|
fn test_actor() -> @identity.PolicyGeneration {
  @identity.PolicyGeneration::initial(test_digest("a"))
}

///|
fn test_tokenizer() -> @experiment.TokenizerIdentity {
  @experiment.TokenizerIdentity::new(test_digest("b"))
}

///|
fn test_request() -> @rollout.RolloutGroupRequest {
  let slots = [
    @rollout.RolloutSlot::new(
      rollout_id=try! @identity.RolloutId::new(11UL),
      sampling=@rollout.SamplingIdentity::new(
        plan_digest=test_digest("c"),
        seed=101UL,
      ),
    ),
    @rollout.RolloutSlot::new(
      rollout_id=try! @identity.RolloutId::new(12UL),
      sampling=@rollout.SamplingIdentity::new(
        plan_digest=test_digest("c"),
        seed=102UL,
      ),
    ),
  ]
  try! @rollout.RolloutGroupRequest::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=@rollout.RolloutRequestId::new(test_digest("d")),
    experiment=@experiment.ExperimentIdentity::new(test_digest("e")),
    dataset=@experiment.DatasetIdentity::new(test_digest("f")),
    group_id=try! @identity.GroupId::new(7UL),
    actor=test_actor(),
    tokenizer=test_tokenizer(),
    limits=try! @rollout.RolloutLimits::new(
      maximum_rollouts=4,
      maximum_prompt_tokens=8,
      maximum_response_tokens=6,
      maximum_token_id=31,
    ),
    selection=try! @rollout.RolloutSelectionPolicy::new(1),
    prompt_tokens=[1, 2, 3],
    slots~,
  )
}

///|
fn test_trajectory(
  rollout_id : @identity.RolloutId,
  terminal : @trajectory.TrajectoryTerminal,
) -> @trajectory.Trajectory {
  let model_token = try! @trajectory.RolloutToken::model(
    token_id=5,
    model_logprob=-1.25,
    sampling_logprob=-0.75,
    maximum_token_id=31,
  )
  let environment_token = try! @trajectory.RolloutToken::environment(
    token_id=6,
    maximum_token_id=31,
  )
  try! @trajectory.Trajectory::new(
    rollout_id~,
    group_id=try! @identity.GroupId::new(7UL),
    policy=test_actor(),
    prompt_tokens=[1, 2, 3],
    response_tokens=[model_token, environment_token],
    terminal~,
    maximum_prompt_tokens=8,
    maximum_response_tokens=6,
    maximum_token_id=31,
  )
}

///|
fn test_response(
  terminal : @rollout.RolloutTerminalEvidence,
  trajectory_terminal : @trajectory.TrajectoryTerminal,
) -> @rollout.RolloutResponse {
  let request = test_request()
  let slot = try! request.slot_at(0)
  try! @rollout.RolloutResponse::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=request.request_id(),
    tokenizer=request.tokenizer(),
    sampling=slot.sampling(),
    trajectory=test_trajectory(slot.rollout_id(), trajectory_terminal),
    terminal~,
    expected_request=request,
  )
}

///|
test "group request owns bounded deterministic N-slot evidence" {
  let request = test_request()
  assert_eq(request.rollout_count(), 2)
  assert_eq(request.prompt_length(), 3)
  assert_eq(request.prompt_token_at(2), 3)
  assert_eq(request.limits().maximum_rollouts(), 4)
  assert_eq(request.limits().maximum_response_tokens(), 6)
  assert_eq(request.slot_at(1).rollout_id().value(), 12UL)
  assert_eq(request.slot_at(1).sampling().seed(), 102UL)
  assert_eq(request.tokenizer().digest(), test_digest("b"))
}

///|
test "protocol hard ceilings reject resource-exhaustion limits" {
  try
    @rollout.RolloutLimits::new(
      maximum_rollouts=4097,
      maximum_prompt_tokens=8,
      maximum_response_tokens=8,
      maximum_token_id=31,
    )
  catch {
    InvalidLimit => ()
    _ => fail("unexpected rollout limit error")
  } noraise {
    _ => fail("unbounded rollout capacity was accepted")
  }
  try
    @rollout.RolloutLimits::new(
      maximum_rollouts=4,
      maximum_prompt_tokens=1048577,
      maximum_response_tokens=8,
      maximum_token_id=31,
    )
  catch {
    InvalidLimit => ()
    _ => fail("unexpected prompt limit error")
  } noraise {
    _ => fail("unbounded prompt capacity was accepted")
  }
  try
    @rollout.RolloutLimits::new(
      maximum_rollouts=4,
      maximum_prompt_tokens=8,
      maximum_response_tokens=1048577,
      maximum_token_id=31,
    )
  catch {
    InvalidLimit => ()
    _ => fail("unexpected response limit error")
  } noraise {
    _ => fail("unbounded response capacity was accepted")
  }
}

///|
test "group request rejects duplicate rollout and sampling identities" {
  let sampling = @rollout.SamplingIdentity::new(
    plan_digest=test_digest("c"),
    seed=101UL,
  )
  let duplicated_rollout = [
    @rollout.RolloutSlot::new(
      rollout_id=try! @identity.RolloutId::new(11UL),
      sampling~,
    ),
    @rollout.RolloutSlot::new(
      rollout_id=try! @identity.RolloutId::new(11UL),
      sampling=@rollout.SamplingIdentity::new(
        plan_digest=test_digest("c"),
        seed=102UL,
      ),
    ),
  ]
  try
    @rollout.RolloutGroupRequest::new(
      protocol_version=@version.ProtocolVersion::v1(),
      request_id=@rollout.RolloutRequestId::new(test_digest("d")),
      experiment=@experiment.ExperimentIdentity::new(test_digest("e")),
      dataset=@experiment.DatasetIdentity::new(test_digest("f")),
      group_id=try! @identity.GroupId::new(7UL),
      actor=test_actor(),
      tokenizer=test_tokenizer(),
      limits=@rollout.RolloutLimits::new(
        maximum_rollouts=2,
        maximum_prompt_tokens=8,
        maximum_response_tokens=6,
        maximum_token_id=31,
      ),
      selection=@rollout.RolloutSelectionPolicy::new(1),
      prompt_tokens=[1],
      slots=duplicated_rollout,
    )
  catch {
    DuplicateRolloutId(index=1) => ()
    _ => fail("unexpected duplicate rollout error")
  } noraise {
    _ => fail("duplicate rollout was accepted")
  }
  let duplicated_sampling = [
    @rollout.RolloutSlot::new(
      rollout_id=try! @identity.RolloutId::new(11UL),
      sampling~,
    ),
    @rollout.RolloutSlot::new(
      rollout_id=try! @identity.RolloutId::new(12UL),
      sampling~,
    ),
  ]
  try
    @rollout.RolloutGroupRequest::new(
      protocol_version=@version.ProtocolVersion::v1(),
      request_id=@rollout.RolloutRequestId::new(test_digest("d")),
      experiment=@experiment.ExperimentIdentity::new(test_digest("e")),
      dataset=@experiment.DatasetIdentity::new(test_digest("f")),
      group_id=try! @identity.GroupId::new(7UL),
      actor=test_actor(),
      tokenizer=test_tokenizer(),
      limits=@rollout.RolloutLimits::new(
        maximum_rollouts=2,
        maximum_prompt_tokens=8,
        maximum_response_tokens=6,
        maximum_token_id=31,
      ),
      selection=@rollout.RolloutSelectionPolicy::new(1),
      prompt_tokens=[1],
      slots=duplicated_sampling,
    )
  catch {
    DuplicateSamplingIdentity(index=1) => ()
    _ => fail("unexpected duplicate sampling error")
  } noraise {
    _ => fail("duplicate sampling identity was accepted")
  }
}

///|
test "unsupported rollout protocol version fails closed" {
  let request = test_request()
  let slot = request.slot_at(0)
  try
    @rollout.RolloutResponse::new(
      protocol_version=@version.ProtocolVersion::new(major=1, minor=1),
      request_id=request.request_id(),
      tokenizer=request.tokenizer(),
      sampling=slot.sampling(),
      trajectory=test_trajectory(slot.rollout_id(), Completed),
      terminal=Complete,
      expected_request=request,
    )
  catch {
    @rollout.RolloutProtocolError::UnsupportedVersion => ()
    _ => fail("unexpected version error")
  } noraise {
    _ => fail("unsupported version was accepted")
  }
}

///|
test "response rejects sampling substitution before producing evidence" {
  let request = test_request()
  let slot = request.slot_at(0)
  try
    @rollout.RolloutResponse::new(
      protocol_version=@version.ProtocolVersion::v1(),
      request_id=request.request_id(),
      tokenizer=request.tokenizer(),
      sampling=@rollout.SamplingIdentity::new(
        plan_digest=test_digest("c"),
        seed=999UL,
      ),
      trajectory=test_trajectory(slot.rollout_id(), Completed),
      terminal=Complete,
      expected_request=request,
    )
  catch {
    SamplingIdentityMismatch => ()
    _ => fail("unexpected sampling substitution error")
  } noraise {
    _ => fail("substituted sampling identity was accepted")
  }
}

///|
test "partial and cancelled terminal evidence cannot be relabeled" {
  let partial = test_response(Partial(ResponseTokenLimit), Truncated)
  assert_true(partial.terminal() is Partial(_))
  let cancelled = test_response(Cancelled(GroupSatisfied), Cancelled)
  assert_eq(cancelled.trajectory().response_length(), 2)
  try
    @rollout.RolloutResponse::new(
      protocol_version=cancelled.protocol_version(),
      request_id=cancelled.request_id(),
      tokenizer=cancelled.tokenizer(),
      sampling=cancelled.sampling(),
      trajectory=cancelled.trajectory(),
      terminal=Complete,
      expected_request=test_request(),
    )
  catch {
    TerminalMismatch => ()
    _ => fail("unexpected terminal mismatch error")
  } noraise {
    _ => fail("cancelled trajectory was relabeled complete")
  }
}

///|
test "teacher forcing binds exact policy and reference targets" {
  let response = test_response(Complete, Completed)
  let policy_target = @rollout.ScoreTarget::Policy(test_actor())
  let request = @rollout.TeacherScoreRequest::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=@rollout.ScoreRequestId::new(test_digest("e")),
    rollout=response,
    target=policy_target,
  )
  let scores = [
    @rollout.TeacherTokenScore::model(model_logprob=-1.5),
    @rollout.TeacherTokenScore::environment(),
  ]
  let evidence = @rollout.TeacherScoreEvidence::new(
    protocol_version=request.protocol_version(),
    request_id=request.request_id(),
    rollout_id=response.trajectory().rollout_id(),
    source_actor=response.trajectory().policy(),
    tokenizer=response.tokenizer(),
    target=policy_target,
    token_scores=scores,
    expected_request=request,
  )
  assert_eq(evidence.token_count(), 2)
  assert_eq(evidence.token_score_at(0).model_logprob(), Some(-1.5))
  assert_false(evidence.token_score_at(1).is_scored())
  let policy_scores = evidence.as_policy_score(response.trajectory())
  assert_eq(policy_scores.target_policy(), test_actor())
  assert_eq(policy_scores.logprob_at(0), Some(-1.5))
  let reference_target = @rollout.ScoreTarget::Reference(test_digest("f"))
  let reference_request = @rollout.TeacherScoreRequest::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=@rollout.ScoreRequestId::new(test_digest("f")),
    rollout=response,
    target=reference_target,
  )
  assert_eq(reference_request.target(), reference_target)
  let reference_evidence = @rollout.TeacherScoreEvidence::new(
    protocol_version=reference_request.protocol_version(),
    request_id=reference_request.request_id(),
    rollout_id=response.trajectory().rollout_id(),
    source_actor=response.trajectory().policy(),
    tokenizer=response.tokenizer(),
    target=reference_target,
    token_scores=scores,
    expected_request=reference_request,
  )
  let reference_scores = reference_evidence.as_reference_score(
    response.trajectory(),
  )
  assert_eq(reference_scores.reference_actor(), test_digest("f"))
}

///|
test "teacher score rejects identity and token-origin substitution" {
  let response = test_response(Complete, Completed)
  let target = @rollout.ScoreTarget::Reference(test_digest("f"))
  let request = @rollout.TeacherScoreRequest::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=@rollout.ScoreRequestId::new(test_digest("e")),
    rollout=response,
    target~,
  )
  try
    @rollout.TeacherScoreEvidence::new(
      protocol_version=request.protocol_version(),
      request_id=@rollout.ScoreRequestId::new(test_digest("d")),
      rollout_id=response.trajectory().rollout_id(),
      source_actor=response.trajectory().policy(),
      tokenizer=response.tokenizer(),
      target~,
      token_scores=[
        @rollout.TeacherTokenScore::model(model_logprob=-1.5),
        @rollout.TeacherTokenScore::environment(),
      ],
      expected_request=request,
    )
  catch {
    ScoreIdentityMismatch => ()
    _ => fail("unexpected score identity error")
  } noraise {
    _ => fail("substituted score request identity was accepted")
  }
  try
    @rollout.TeacherScoreEvidence::new(
      protocol_version=request.protocol_version(),
      request_id=request.request_id(),
      rollout_id=response.trajectory().rollout_id(),
      source_actor=response.trajectory().policy(),
      tokenizer=response.tokenizer(),
      target~,
      token_scores=[
        @rollout.TeacherTokenScore::model(model_logprob=-1.5),
        @rollout.TeacherTokenScore::model(model_logprob=-2.0),
      ],
      expected_request=request,
    )
  catch {
    ScoreOriginMismatch(index=1) => ()
    _ => fail("unexpected token-origin error")
  } noraise {
    _ => fail("environment token received a model score")
  }
}

///|
test "cancelled evidence is ineligible for teacher forcing" {
  let cancelled = test_response(Cancelled(OperatorRequested), Cancelled)
  try
    @rollout.TeacherScoreRequest::new(
      protocol_version=@version.ProtocolVersion::v1(),
      request_id=@rollout.ScoreRequestId::new(test_digest("e")),
      rollout=cancelled,
      target=Reference(test_digest("f")),
    )
  catch {
    IneligibleForScoring => ()
    _ => fail("unexpected scoring eligibility error")
  } noraise {
    _ => fail("cancelled evidence was admitted for scoring")
  }
}
