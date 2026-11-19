///|
fn digest_a() -> @identity.Sha256Digest raise {
  @identity.Sha256Digest::parse(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
}

///|
fn digest_b() -> @identity.Sha256Digest raise {
  @identity.Sha256Digest::parse(
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
}

///|
fn digest_c() -> @identity.Sha256Digest raise {
  @identity.Sha256Digest::parse(
    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  )
}

///|
fn digest_d() -> @identity.Sha256Digest raise {
  @identity.Sha256Digest::parse(
    "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
}

///|
fn initial_policy() -> @identity.PolicyGeneration raise {
  @identity.PolicyGeneration::initial(digest_a())
}

///|
fn next_policy() -> @identity.PolicyGeneration raise {
  @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=digest_b(),
    parent_actor=Some(digest_a()),
  )
}

///|
fn item(
  rollout_value : UInt64,
  token_count : Int32,
) -> @update.TrainingItemRef raise {
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
  let tokens = [model]
  let targets = [1.0]
  for _ in 1..<token_count {
    tokens.push(environment)
    targets.push(0.0)
  }
  let trajectory = @trajectory.Trajectory::new(
    rollout_id=@identity.RolloutId::new(rollout_value),
    group_id=@identity.GroupId::new(1UL),
    policy=initial_policy(),
    prompt_tokens=[1],
    response_tokens=tokens,
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=8,
    maximum_token_id=31,
  )
  @update.TrainingItemRef::new(
    trajectory=trajectory.evidence_identity(),
    target_values=targets,
  )
}

///|
fn batch_with(
  items : ArrayView[@update.TrainingItemRef],
) -> @update.TrainingBatch raise {
  @update.TrainingBatch::new(
    id=@update.TrainingBatchId::new(9UL),
    policy=initial_policy(),
    items~,
    maximum_items=8,
    maximum_total_tokens=32,
    maximum_trainable_tokens=8,
  )
}

///|
test "batch references are immutable, bounded, and policy exact" {
  let first = item(1UL, 3)
  let second = item(2UL, 3)
  let batch = batch_with([first, second])
  assert_eq(batch.item_count(), 2)
  assert_eq(batch.total_token_count(), 6)
  assert_eq(batch.trainable_token_count(), 2)
  assert_eq(batch.item_at(1).rollout_id().value(), 2UL)
  assert_eq(batch.item_at(0).target_value_at(0), 1.0)
}

///|
test "duplicate rollout is rejected" {
  let first = item(1UL, 3)
  try batch_with([first, first]) catch {
    @update.DuplicateRollout => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected duplicate rejection")
  }
}

///|
test "batch rollout references require canonical order" {
  let first = item(2UL, 3)
  let second = item(1UL, 3)
  try batch_with([first, second]) catch {
    @update.NonCanonicalRolloutOrder => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected canonical-order rejection")
  }
}

///|
test "trainable token limit is enforced before construction" {
  let first = item(1UL, 3)
  let second = item(2UL, 3)
  try
    @update.TrainingBatch::new(
      id=@update.TrainingBatchId::new(9UL),
      policy=initial_policy(),
      items=[first, second],
      maximum_items=8,
      maximum_total_tokens=32,
      maximum_trainable_tokens=1,
    )
  catch {
    @update.TrainableTokenLimitExceeded => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected token-limit rejection")
  }
}

///|
test "total token limit is overflow-safe and independent of trainability" {
  let first = item(1UL, 7)
  let second = item(2UL, 7)
  try
    @update.TrainingBatch::new(
      id=@update.TrainingBatchId::new(9UL),
      policy=initial_policy(),
      items=[first, second],
      maximum_items=8,
      maximum_total_tokens=10,
      maximum_trainable_tokens=8,
    )
  catch {
    @update.TotalTokenLimitExceeded => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected total-token rejection")
  }
}

///|
test "candidate and optimizer evidence retain exact lineage" {
  let first = item(1UL, 3)
  let batch = batch_with([first])
  let candidate = @update.CandidatePolicy::new(
    parent=initial_policy(),
    target=next_policy(),
    artifact_digest=digest_b(),
    tensor_vocabulary_digest=digest_d(),
  )
  let evidence = @update.OptimizerStepEvidence::new(
    step_id=@update.OptimizerStepId::new(3UL),
    batch~,
    candidate~,
    optimizer_state_digest=digest_c(),
    trained_token_count=1,
    mean_loss=0.25,
  )
  assert_eq(evidence.batch_id(), batch.id())
  assert_eq(evidence.parent(), initial_policy())
  assert_eq(evidence.target(), next_policy())
  assert_eq(evidence.candidate_digest(), digest_b())
}

///|
test "candidate artifact digest must be the target actor" {
  try
    @update.CandidatePolicy::new(
      parent=initial_policy(),
      target=next_policy(),
      artifact_digest=digest_c(),
      tensor_vocabulary_digest=digest_d(),
    )
  catch {
    @update.CandidateDigestMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected candidate digest rejection")
  }
}

///|
test "optimizer evidence rejects partial token accounting" {
  let first = item(1UL, 3)
  let batch = batch_with([first])
  let candidate = @update.CandidatePolicy::new(
    parent=initial_policy(),
    target=next_policy(),
    artifact_digest=digest_b(),
    tensor_vocabulary_digest=digest_d(),
  )
  try
    @update.OptimizerStepEvidence::new(
      step_id=@update.OptimizerStepId::new(3UL),
      batch~,
      candidate~,
      optimizer_state_digest=digest_c(),
      trained_token_count=0,
      mean_loss=0.25,
    )
  catch {
    @update.StepTokenMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected token-accounting rejection")
  }
}
