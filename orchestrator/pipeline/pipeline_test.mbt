///|
fn pipeline_owner(
  manifest : @experiment.ExperimentManifest,
  maximum_staleness : Int32,
) -> @pipeline.PipelineOwner {
  try! @pipeline.PipelineOwner::new(
    manifest~,
    staleness_policy=try! @staleness.StalenessPolicy::new(maximum_staleness),
  )
}

///|
test "training-ready but uncommitted cycle cannot retire" {
  let (first, _, _) = pipeline_policies()
  let manifest = pipeline_manifest(first, "8", 1UL)
  let request = pipeline_request(manifest, 1UL)
  let owner = pipeline_owner(manifest, 1)
  let cycle = owner.open_cycle(manifest, request)
  ignore(pipeline_make_ready(cycle, request))
  try owner.retire_oldest() catch {
    OldestNotRetirable(actual=ReadyForTraining) => ()
    _ => fail("unexpected uncommitted-cycle retirement error")
  } noraise {
    _ => fail("training-ready cycle retired before publication commit")
  }
  assert_eq(owner.in_flight_count(), 1)
}

///|
test "manifest components and limits cannot be substituted" {
  let (first, second, _) = pipeline_policies()
  let manifest = pipeline_manifest(first, "8", 1UL)
  let dataset_substitution = pipeline_manifest(second, "d", 1UL)
  try
    pipeline_owner(manifest, 1).open_cycle(
      dataset_substitution,
      pipeline_request(dataset_substitution, 2UL),
    )
  catch {
    ManifestMismatch => ()
    _ => fail("unexpected component-substitution error")
  } noraise {
    _ => fail("substituted dataset entered the pipeline")
  }
  let base = pipeline_manifest(second, "8", 1UL)
  let limits_substitution = @experiment.ExperimentManifest::new(
    identity=base.identity(),
    actor=base.actor(),
    dataset=base.dataset(),
    reward_policy=base.reward_policy(),
    tokenizer=base.tokenizer(),
    algorithm=base.algorithm(),
    limits=@experiment.ExperimentLimits::new(
      concurrent_groups=@experiment.ConcurrentGroupCapacity::new(1UL),
      rollouts_per_group=base.limits().rollouts_per_group(),
      prompt_tokens=base.limits().prompt_tokens(),
      response_tokens=base.limits().response_tokens(),
      pending_updates=base.limits().pending_updates(),
    ),
  )
  try
    pipeline_owner(manifest, 1).open_cycle(
      limits_substitution,
      pipeline_request(limits_substitution, 2UL),
    )
  catch {
    ManifestMismatch => ()
    _ => fail("unexpected limit-substitution error")
  } noraise {
    _ => fail("substituted limits entered the pipeline")
  }
}

///|
test "cycle request is bound to the exact manifest actor" {
  let (first, second, _) = pipeline_policies()
  let manifest = pipeline_manifest(first, "8", 1UL)
  let substituted_manifest = pipeline_manifest(second, "8", 1UL)
  let owner = pipeline_owner(manifest, 1)
  try
    owner.open_cycle(manifest, pipeline_request(substituted_manifest, 1UL))
  catch {
    Cycle(RequestMismatch) => ()
    _ => fail("unexpected request-substitution error")
  } noraise {
    _ => fail("request for another actor entered the cycle")
  }
  assert_eq(owner.in_flight_count(), 0)
}

///|
test "completed and aborted cycles retire in actor order" {
  let (first, second, _) = pipeline_policies()
  let first_manifest = pipeline_manifest(first, "8", 1UL)
  let second_manifest = pipeline_manifest(second, "8", 1UL)
  let first_request = pipeline_request(first_manifest, 1UL)
  let second_request = pipeline_request(second_manifest, 2UL)
  let owner = pipeline_owner(first_manifest, 1)
  let first_cycle = owner.open_cycle(first_manifest, first_request)
  pipeline_complete(first_cycle, first_request, second)
  let completed = owner.retire_oldest()
  assert_eq(completed.actor(), first)
  assert_eq(completed.outcome(), Committed(second))
  let second_cycle = owner.open_cycle(second_manifest, second_request)
  try! second_cycle.abort(OperatorRequested)
  let aborted = owner.retire_oldest()
  assert_eq(aborted.actor(), second)
  assert_eq(aborted.outcome(), Aborted(OperatorRequested))
  assert_eq(owner.state(), Drained)
}

///|
test "capacity is the tighter manifest and staleness bound" {
  let (first, _, _) = pipeline_policies()
  let manifest = pipeline_manifest(first, "8", 1UL)
  assert_eq(pipeline_owner(manifest, 1).maximum_in_flight(), 1)
  assert_eq(pipeline_owner(manifest, 8).maximum_in_flight(), 1)
}

///|
test "serial v1 applies backpressure and pipeline-owned staleness bounds" {
  let (first, second, _) = pipeline_policies()
  let first_manifest = pipeline_manifest(first, "8", 1UL)
  let owner = pipeline_owner(first_manifest, 1)
  ignore(
    owner.open_cycle(first_manifest, pipeline_request(first_manifest, 1UL)),
  )
  try
    owner.open_cycle(first_manifest, pipeline_request(first_manifest, 2UL))
  catch {
    Backpressure => ()
    _ => fail("unexpected serial-backpressure error")
  } noraise {
    _ => fail("a second pending update bypassed v1 serialization")
  }
  let target_manifest = pipeline_manifest(second, "8", 1UL)
  let bounded = pipeline_owner(target_manifest, 0)
  try
    bounded.open_stale_cycle(
      target_manifest,
      pipeline_request(first_manifest, 3UL),
      [first, second],
    )
  catch {
    Staleness(ExceedsMaximum(actual=1, maximum=0)) => ()
    _ => fail("unexpected stale-bound error")
  } noraise {
    _ => fail("stale replay bypassed the owner policy")
  }
}

///|
test "pipeline-owned stale replay requires and trains exact correction" {
  let (source, target, successor) = pipeline_policies()
  let source_manifest = pipeline_manifest(source, "8", 1UL)
  let target_manifest = pipeline_manifest(target, "8", 1UL)
  let request = pipeline_request(source_manifest, 1UL)
  let owner = pipeline_owner(target_manifest, 1)
  let cycle = owner.open_stale_cycle(target_manifest, request, [source, target])
  let response = pipeline_response(request)
  let trajectory = response.trajectory()
  let advantage = pipeline_advantage(trajectory)
  cycle.admit_rollout(response)
  cycle.seal_rollouts()
  try cycle.accept_advantage(advantage) catch {
    CorrectionRequired => ()
    _ => fail("unexpected stale-uncorrected error")
  } noraise {
    _ => fail("stale evidence bypassed importance correction")
  }
  guard cycle.staleness() is Some(staleness) else {
    fail("pipeline dropped its staleness witness")
  }
  let target_scores = @reward.PolicyScoreEvidence::new(
    trajectory,
    target_policy=target,
    logprobs=[Some(-1.0), None],
  )
  let correction = @correction.ImportanceCorrectionEvidence::new(
    trajectory,
    staleness,
    target_scores,
    @correction.ImportanceBounds::new(
      minimum_ratio=0.5,
      maximum_ratio=2.0,
      denominator=BehaviorModel,
    ),
  )
  let corrected = @correction.CorrectedAdvantageEvidence::new(
    advantage, correction,
  )
  cycle.accept_corrected_advantage(corrected)
  let batch = @update.TrainingBatch::new(
    id=@update.TrainingBatchId::new(2UL),
    policy=target,
    items=[corrected.training_item()],
    maximum_items=4,
    maximum_total_tokens=16,
    maximum_trainable_tokens=8,
  )
  let training = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(2UL),
    batch~,
  )
  cycle.prepare_training(training)
  cycle.dispatch_training()
  let candidate = @update.CandidatePolicy::new(
    parent=target,
    target=successor,
    artifact_digest=successor.actor(),
    tensor_vocabulary_digest=pipeline_digest("f"),
  )
  let step = @update.OptimizerStepEvidence::new(
    step_id=@update.OptimizerStepId::new(2UL),
    batch~,
    candidate~,
    optimizer_state_digest=pipeline_digest("e"),
    trained_token_count=1,
    mean_loss=0.25,
  )
  cycle.accept_trainer_result(
    @trainer.TrainerStepResult::new(request=training, evidence=step, candidate~),
  )
  cycle.accept_committed_publication(pipeline_committed_publication(candidate))
  cycle.finish()
  assert_eq(owner.retire_oldest().outcome(), Committed(successor))
}

///|
test "quiescent checkpoint binds exact manifest actor and committed successor" {
  let (first, second, third) = pipeline_policies()
  let manifest = pipeline_manifest(first, "8", 1UL)
  let request = pipeline_request(manifest, 1UL)
  let owner = pipeline_owner(manifest, 1)
  let cycle = owner.open_cycle(manifest, request)
  try owner.checkpoint() catch {
    CheckpointRequiresQuiescence => ()
    _ => fail("unexpected live-checkpoint error")
  } noraise {
    _ => fail("live cycle was misrepresented as a recoverable checkpoint")
  }
  pipeline_complete(cycle, request, second)
  ignore(owner.retire_oldest())
  let checkpoint = owner.checkpoint()
  assert_eq(checkpoint.manifest().actor(), first)
  assert_eq(checkpoint.required_next_policy(), Some(second))
  let persisted = @pipeline.QuiescentCheckpoint::new(
    manifest=checkpoint.manifest(),
    staleness_policy=checkpoint.staleness_policy(),
    last_opened=checkpoint.last_opened_policy(),
    required_next=checkpoint.required_next_policy(),
    retired_count=checkpoint.retired_count(),
    state=checkpoint.state(),
  )
  let restored = @pipeline.PipelineOwner::restore(persisted)
  let second_manifest = pipeline_manifest(second, "8", 1UL)
  ignore(
    restored.open_cycle(second_manifest, pipeline_request(second_manifest, 2UL)),
  )
  let unrelated = pipeline_manifest(third, "8", 1UL)
  try
    @pipeline.QuiescentCheckpoint::new(
      manifest=unrelated,
      staleness_policy=checkpoint.staleness_policy(),
      last_opened=Some(first),
      required_next=Some(second),
      retired_count=1UL,
      state=Accepting,
    )
  catch {
    InvalidCheckpoint => ()
    _ => fail("unexpected checkpoint actor-substitution error")
  } noraise {
    _ => fail("checkpoint accepted an unrelated manifest actor")
  }
}

///|
test "drain and cancellation go through UpdateCycle" {
  let (first, _, _) = pipeline_policies()
  let manifest = pipeline_manifest(first, "8", 1UL)
  let request = pipeline_request(manifest, 1UL)
  let owner = pipeline_owner(manifest, 1)
  ignore(owner.open_cycle(manifest, request))
  owner.begin_drain()
  owner.cancel_generation(first, OperatorRequested)
  let snapshot = owner.snapshot()
  assert_eq(snapshot.generation_at(0).state(), CycleAborted)
  assert_eq(snapshot.generation_at(0).abort_reason(), Some(OperatorRequested))
  ignore(owner.retire_oldest())
  assert_eq(owner.state(), Drained)
}
