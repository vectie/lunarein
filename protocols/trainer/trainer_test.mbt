///|
fn digest(value : String) -> @identity.Sha256Digest raise {
  @identity.Sha256Digest::parse(value)
}

///|
fn parent_policy() -> @identity.PolicyGeneration raise {
  @identity.PolicyGeneration::initial(
    digest("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
}

///|
fn target_policy() -> @identity.PolicyGeneration raise {
  @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=digest(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
    parent_actor=Some(parent_policy().actor()),
  )
}

///|
fn training_batch(id : UInt64) -> @update.TrainingBatch raise {
  let model = @trajectory.RolloutToken::model(
    token_id=7,
    model_logprob=-1.0,
    sampling_logprob=-1.0,
    maximum_token_id=31,
  )
  let environment = @trajectory.RolloutToken::environment(
    token_id=8,
    maximum_token_id=31,
  )
  let trajectory = @trajectory.Trajectory::new(
    rollout_id=@identity.RolloutId::new(id),
    group_id=@identity.GroupId::new(1UL),
    policy=parent_policy(),
    prompt_tokens=[1],
    response_tokens=[model, model, environment, environment],
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=31,
  )
  let item = @update.TrainingItemRef::new(
    trajectory=trajectory.evidence_identity(),
    target_values=[1.0, 1.0, 0.0, 0.0],
  )
  @update.TrainingBatch::new(
    id=@update.TrainingBatchId::new(id),
    policy=parent_policy(),
    items=[item],
    maximum_items=2,
    maximum_total_tokens=8,
    maximum_trainable_tokens=4,
  )
}

///|
fn candidate() -> @update.CandidatePolicy raise {
  @update.CandidatePolicy::new(
    parent=parent_policy(),
    target=target_policy(),
    artifact_digest=target_policy().actor(),
    tensor_vocabulary_digest=digest(
      "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    ),
  )
}

///|
fn result_for(
  request : @trainer.TrainingRequest,
) -> @trainer.TrainerStepResult raise {
  let batch = request.batch()
  let next = candidate()
  let evidence = @update.OptimizerStepEvidence::new(
    step_id=@update.OptimizerStepId::new(request.id().value()),
    batch~,
    candidate=next,
    optimizer_state_digest=digest(
      "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    ),
    trained_token_count=batch.trainable_token_count(),
    mean_loss=0.125,
  )
  @trainer.TrainerStepResult::new(request~, evidence~, candidate=next)
}

///|
test "trainer transaction accepts one exact result" {
  let request = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(7UL),
    batch=training_batch(7UL),
  )
  let transaction = @trainer.TrainerTransaction::new(request)
  assert_eq(transaction.state(), Prepared)
  transaction.dispatch()
  transaction.accept_result(result_for(request))
  assert_eq(transaction.state(), ResultAccepted)
  transaction.complete()
  assert_eq(transaction.state(), Completed)
  guard transaction.result() is Some(result) else {
    fail("missing accepted result")
  }
  assert_eq(result.request_id(), request.id())
  assert_eq(result.candidate().target(), target_policy())
}

///|
test "result from another request is rejected before mutation" {
  let request = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(7UL),
    batch=training_batch(7UL),
  )
  let other = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(8UL),
    batch=training_batch(8UL),
  )
  let transaction = @trainer.TrainerTransaction::new(request)
  transaction.dispatch()
  try transaction.accept_result(result_for(other)) catch {
    @trainer.BatchMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected mismatched request rejection")
  }
  assert_eq(transaction.state(), Dispatched)
  assert_true(transaction.result() is None)
}

///|
test "failure is terminal and carries a typed reason" {
  let request = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(7UL),
    batch=training_batch(7UL),
  )
  let transaction = @trainer.TrainerTransaction::new(request)
  transaction.dispatch()
  transaction.fail(NumericalFailure)
  assert_eq(transaction.state(), Failed)
  assert_eq(transaction.failure(), Some(NumericalFailure))
  try transaction.dispatch() catch {
    InvalidState(expected=_, actual=_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected terminal-state rejection")
  }
}

///|
test "trainer uses the common exact protocol version" {
  let batch = training_batch(9UL)
  let request = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(9UL),
    batch~,
  )
  assert_eq(request.version(), @version.ProtocolVersion::v1())
  try
    @trainer.TrainingRequest::new_versioned(
      version=@version.ProtocolVersion::new(major=1, minor=1),
      id=@trainer.TrainingRequestId::new(10UL),
      batch~,
    )
  catch {
    @trainer.UnsupportedVersion => ()
    _ => fail("unexpected trainer-version error")
  } noraise {
    _ => fail("unsupported trainer version was accepted")
  }
}
