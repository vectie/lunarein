///|
fn cycle_digest(character : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(character.repeat(64))
}

///|
fn cycle_actor() -> @identity.PolicyGeneration {
  @identity.PolicyGeneration::initial(cycle_digest("a"))
}

///|
fn cycle_manifest_with_tokenizer(
  tokenizer_digest : @identity.Sha256Digest,
  algorithm_kind : @experiment.AlgorithmKind,
) -> @experiment.ExperimentManifest {
  @experiment.ExperimentManifest::new(
    identity=@experiment.ExperimentIdentity::new(cycle_digest("9")),
    actor=cycle_actor(),
    dataset=@experiment.DatasetIdentity::new(cycle_digest("8")),
    reward_policy=@experiment.RewardPolicyIdentity::new(cycle_digest("7")),
    tokenizer=@experiment.TokenizerIdentity::new(tokenizer_digest),
    algorithm=@experiment.AlgorithmIdentity::new(
      cycle_digest("6"),
      algorithm_kind,
    ),
    limits=@experiment.ExperimentLimits::new(
      concurrent_groups=try! @experiment.ConcurrentGroupCapacity::new(2UL),
      rollouts_per_group=try! @experiment.RolloutsPerGroupCapacity::new(4UL),
      prompt_tokens=try! @experiment.PromptTokenCapacity::new(8UL),
      response_tokens=try! @experiment.ResponseTokenCapacity::new(6UL),
      pending_updates=try! @experiment.PendingUpdateCapacity::new(1UL),
    ),
  )
}

///|
fn cycle_manifest() -> @experiment.ExperimentManifest {
  cycle_manifest_with_tokenizer(cycle_digest("b"), Reinforce)
}

///|
fn cycle_request_for(
  rollout_value : UInt64,
  group_value : UInt64,
  request_digest : @identity.Sha256Digest,
) -> @rollout.RolloutGroupRequest {
  let sampling = @rollout.SamplingIdentity::new(
    plan_digest=cycle_digest("c"),
    seed=rollout_value,
  )
  let slot = @rollout.RolloutSlot::new(
    rollout_id=try! @identity.RolloutId::new(rollout_value),
    sampling~,
  )
  try! @rollout.RolloutGroupRequest::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=@rollout.RolloutRequestId::new(request_digest),
    experiment=@experiment.ExperimentIdentity::new(cycle_digest("9")),
    dataset=@experiment.DatasetIdentity::new(cycle_digest("8")),
    group_id=try! @identity.GroupId::new(group_value),
    actor=cycle_actor(),
    tokenizer=@experiment.TokenizerIdentity::new(cycle_digest("b")),
    limits=try! @rollout.RolloutLimits::new(
      maximum_rollouts=4,
      maximum_prompt_tokens=8,
      maximum_response_tokens=6,
      maximum_token_id=31,
    ),
    selection=try! @rollout.RolloutSelectionPolicy::new(1),
    prompt_tokens=[1, 2, 3],
    slots=[slot],
  )
}

///|
fn cycle_request() -> @rollout.RolloutGroupRequest {
  cycle_request_for(11UL, 7UL, cycle_digest("d"))
}

///|
fn cycle_response_for(
  request : @rollout.RolloutGroupRequest,
  terminal : @rollout.RolloutTerminalEvidence,
  trajectory_terminal : @trajectory.TrajectoryTerminal,
) -> @rollout.RolloutResponse {
  let sampling = (try! request.slot_at(0)).sampling()
  let slot = try! request.slot_at(0)
  let model = try! @trajectory.RolloutToken::model(
    token_id=5,
    model_logprob=-1.25,
    sampling_logprob=-0.75,
    maximum_token_id=31,
  )
  let environment = try! @trajectory.RolloutToken::environment(
    token_id=6,
    maximum_token_id=31,
  )
  let trajectory = try! @trajectory.Trajectory::new(
    rollout_id=slot.rollout_id(),
    group_id=request.group_id(),
    policy=request.actor(),
    prompt_tokens=[1, 2, 3],
    response_tokens=[model, environment],
    terminal=trajectory_terminal,
    maximum_prompt_tokens=8,
    maximum_response_tokens=6,
    maximum_token_id=31,
  )
  try! @rollout.RolloutResponse::new(
    protocol_version=request.protocol_version(),
    request_id=request.request_id(),
    tokenizer=request.tokenizer(),
    sampling~,
    trajectory~,
    terminal~,
    expected_request=request,
  )
}

///|
fn cycle_response(
  terminal : @rollout.RolloutTerminalEvidence,
  trajectory_terminal : @trajectory.TrajectoryTerminal,
) -> @rollout.RolloutResponse {
  cycle_response_for(cycle_request(), terminal, trajectory_terminal)
}

///|
fn cycle_advantage(
  trajectory : @trajectory.Trajectory,
) -> @advantage.AdvantageEvidence {
  let source = @reward.RewardSourceId::new(cycle_digest("7"))
  let scalar = try! @reward.ScalarRewardEvidence::new(
    trajectory,
    source~,
    value=1.0,
  )
  let tokens = try! @reward.TokenRewardEvidence::new(trajectory, source~, values=[
    0.0, 0.0,
  ])
  try! @advantage.reinforce_returns(
    trajectory,
    scalar,
    tokens,
    discount=1.0,
    algorithm=@experiment.AlgorithmIdentity::new(cycle_digest("6"), Reinforce),
  )
}

///|
fn cycle_training_request(
  evidence : @advantage.AdvantageEvidence,
) -> @trainer.TrainingRequest {
  let item = try! evidence.training_item()
  let batch = try! @update.TrainingBatch::new(
    id=try! @update.TrainingBatchId::new(1UL),
    policy=evidence.policy(),
    items=[item],
    maximum_items=4,
    maximum_total_tokens=16,
    maximum_trainable_tokens=8,
  )
  @trainer.TrainingRequest::new(
    id=try! @trainer.TrainingRequestId::new(1UL),
    batch~,
  )
}

///|
fn cycle_candidate() -> @update.CandidatePolicy {
  let parent = cycle_actor()
  let target = try! @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=cycle_digest("1"),
    parent_actor=Some(parent.actor()),
  )
  try! @update.CandidatePolicy::new(
    parent~,
    target~,
    artifact_digest=target.actor(),
    tensor_vocabulary_digest=cycle_digest("2"),
  )
}

///|
fn committed_publication(
  candidate : @update.CandidatePolicy,
) -> @publication.PublicationOwner raise {
  let manifest = try! @publication.FullArtifactManifest::new(
    id=try! @publication.PublicationId::new(1UL),
    candidate~,
    total_bytes=4L,
    chunk_bytes=4,
    rollout_rank_count=1,
    maximum_artifact_bytes=1024L,
    maximum_chunk_bytes=16,
    maximum_chunks=4,
    maximum_rollout_ranks=4,
  )
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(@publication.ReservationEvidence::reserved(manifest))
  owner.begin_transport(FullArtifactV1)
  owner.accept_chunk(
    @publication.ArtifactChunkEvidence::new(
      manifest~,
      index=0,
      chunk_digest=cycle_digest("3"),
    ),
  )
  owner.verify_artifact(manifest.artifact_digest())
  owner.accept_acknowledgement(
    @publication.RolloutRankAcknowledgement::new(
      manifest~,
      rank=0,
      observed_artifact_digest=manifest.artifact_digest(),
    ),
  )
  owner.commit()
  owner
}

///|
test "one update cycle composes rollout through committed policy" {
  let response = cycle_response(Complete, Completed)
  let trajectory = response.trajectory()
  let cycle = @cycle.UpdateCycle::new(cycle_manifest(), cycle_request())
  cycle.admit_rollout(response)
  cycle.seal_rollouts()
  let advantage = cycle_advantage(trajectory)
  cycle.accept_advantage(advantage)
  let request = cycle_training_request(advantage)
  cycle.prepare_training(request)
  cycle.dispatch_training()
  let candidate = cycle_candidate()
  let evidence = @update.OptimizerStepEvidence::new(
    step_id=@update.OptimizerStepId::new(1UL),
    batch=request.batch(),
    candidate~,
    optimizer_state_digest=cycle_digest("4"),
    trained_token_count=1,
    mean_loss=0.25,
  )
  cycle.accept_trainer_result(
    @trainer.TrainerStepResult::new(request~, evidence~, candidate~),
  )
  cycle.accept_committed_publication(committed_publication(candidate))
  cycle.finish()
  assert_eq(cycle.state(), CycleCompleted)
  assert_eq(cycle.committed_policy(), Some(candidate.target()))
  assert_eq(cycle.rollout_count(), 1)
  assert_eq(cycle.advantage_count(), 1)
}

///|
test "cancelled rollout is accounted but cannot satisfy selection" {
  let cancelled = cycle_response(Cancelled(OperatorRequested), Cancelled)
  let cycle = @cycle.UpdateCycle::new(cycle_manifest(), cycle_request())
  cycle.admit_rollout(cancelled)
  assert_eq(cycle.terminal_count(), 1)
  assert_eq(cycle.usable_count(), 0)
  try cycle.seal_rollouts() catch {
    InsufficientUsableRollouts => ()
    _ => fail("unexpected selection error")
  } noraise {
    _ => fail("cancelled rollout satisfied the usable selection")
  }
  assert_eq(cycle.state(), GatheringRollouts)
}

///|
test "rollout tokenizer must match the digest-pinned experiment" {
  try
    @cycle.UpdateCycle::new(
      cycle_manifest_with_tokenizer(cycle_digest("5"), Reinforce),
      cycle_request(),
    )
  catch {
    RequestMismatch => ()
    _ => fail("unexpected tokenizer-substitution error")
  } noraise {
    _ => fail("request from another tokenizer entered the experiment")
  }
}

///|
test "reward policy and algorithm identities are enforced at the join" {
  let base = cycle_manifest()
  let reward_substitution = @experiment.ExperimentManifest::new(
    identity=base.identity(),
    actor=base.actor(),
    dataset=base.dataset(),
    reward_policy=@experiment.RewardPolicyIdentity::new(cycle_digest("5")),
    tokenizer=base.tokenizer(),
    algorithm=base.algorithm(),
    limits=base.limits(),
  )
  let response = cycle_response(Complete, Completed)
  let trajectory = response.trajectory()
  let reward_cycle = @cycle.UpdateCycle::new(
    reward_substitution,
    cycle_request(),
  )
  reward_cycle.admit_rollout(response)
  reward_cycle.seal_rollouts()
  try reward_cycle.accept_advantage(cycle_advantage(trajectory)) catch {
    RewardPolicyMismatch => ()
    _ => fail("unexpected reward-policy error")
  } noraise {
    _ => fail("evidence from another reward policy was accepted")
  }
  let algorithm_substitution = @experiment.ExperimentManifest::new(
    identity=base.identity(),
    actor=base.actor(),
    dataset=base.dataset(),
    reward_policy=base.reward_policy(),
    tokenizer=base.tokenizer(),
    algorithm=@experiment.AlgorithmIdentity::new(cycle_digest("5"), Reinforce),
    limits=base.limits(),
  )
  let algorithm_response = cycle_response(Complete, Completed)
  let algorithm_trajectory = algorithm_response.trajectory()
  let algorithm_cycle = @cycle.UpdateCycle::new(
    algorithm_substitution,
    cycle_request(),
  )
  algorithm_cycle.admit_rollout(algorithm_response)
  algorithm_cycle.seal_rollouts()
  try
    algorithm_cycle.accept_advantage(cycle_advantage(algorithm_trajectory))
  catch {
    AlgorithmMismatch => ()
    _ => fail("unexpected algorithm-identity error")
  } noraise {
    _ => fail("evidence from another algorithm identity was accepted")
  }
}

///|
test "training shape substitution fails before transaction creation" {
  let response = cycle_response(Complete, Completed)
  let trajectory = response.trajectory()
  let cycle = @cycle.UpdateCycle::new(cycle_manifest(), cycle_request())
  cycle.admit_rollout(response)
  cycle.seal_rollouts()
  cycle.accept_advantage(cycle_advantage(trajectory))
  let substituted_item = @update.TrainingItemRef::new(
    trajectory=trajectory.evidence_identity(),
    target_values=[2.0, 0.0],
  )
  let batch = @update.TrainingBatch::new(
    id=@update.TrainingBatchId::new(2UL),
    policy=trajectory.policy(),
    items=[substituted_item],
    maximum_items=4,
    maximum_total_tokens=16,
    maximum_trainable_tokens=8,
  )
  let request = @trainer.TrainingRequest::new(
    id=@trainer.TrainingRequestId::new(2UL),
    batch~,
  )
  try cycle.prepare_training(request) catch {
    TrainingShapeMismatch => ()
    _ => fail("unexpected training-shape error")
  } noraise {
    _ => fail("substituted training shape was accepted")
  }
  assert_eq(cycle.state(), ReadyForTraining)
}

///|
test "PPO value targets follow the same exact trainer transaction path" {
  let response = cycle_response(Complete, Completed)
  let trajectory = response.trajectory()
  let source = @reward.RewardSourceId::new(cycle_digest("7"))
  let scalar = @reward.ScalarRewardEvidence::new(trajectory, source~, value=1.0)
  let token_rewards = @reward.TokenRewardEvidence::new(trajectory, source~, values=[
    0.0, 0.0,
  ])
  let state_values = @advantage.StateValueEvidence::new(trajectory, values=[
    0.25, 0.0, 0.0,
  ])
  let targets = @advantage.gae_ppo_targets(
    trajectory,
    scalar,
    token_rewards,
    state_values,
    discount=1.0,
    trace_decay=1.0,
    algorithm=@experiment.AlgorithmIdentity::new(cycle_digest("6"), GaePpo),
  )
  let cycle = @cycle.UpdateCycle::new(
    cycle_manifest_with_tokenizer(cycle_digest("b"), GaePpo),
    cycle_request(),
  )
  cycle.admit_rollout(response)
  cycle.seal_rollouts()
  cycle.accept_ppo_target(targets)
  let batch = @update.TrainingBatch::new(
    id=@update.TrainingBatchId::new(3UL),
    policy=trajectory.policy(),
    items=[targets.training_item()],
    maximum_items=4,
    maximum_total_tokens=16,
    maximum_trainable_tokens=8,
  )
  cycle.prepare_training(
    @trainer.TrainingRequest::new(
      id=@trainer.TrainingRequestId::new(3UL),
      batch~,
    ),
  )
  assert_eq(cycle.state(), TrainerPrepared)
  assert_true(batch.item_at(0).has_value_returns())
}

///|
test "one update cycle batches multiple exact prompt groups" {
  let first_request = cycle_request()
  let second_request = cycle_request_for(12UL, 8UL, cycle_digest("5"))
  let first_response = cycle_response_for(first_request, Complete, Completed)
  let second_response = cycle_response_for(second_request, Complete, Completed)
  let first_trajectory = first_response.trajectory()
  let second_trajectory = second_response.trajectory()
  let first_advantage = cycle_advantage(first_trajectory)
  let second_advantage = cycle_advantage(second_trajectory)
  let cycle = @cycle.UpdateCycle::new(cycle_manifest(), first_request)
  cycle.add_group(second_request)
  cycle.admit_rollout(first_response)
  try cycle.seal_rollouts() catch {
    IncompleteRolloutSet => ()
    _ => fail("unexpected incomplete-group error")
  } noraise {
    _ => fail("cycle sealed before every group reached a terminal outcome")
  }
  cycle.admit_rollout(second_response)
  cycle.seal_rollouts()
  cycle.accept_advantage(first_advantage)
  cycle.accept_advantage(second_advantage)
  let batch = @update.TrainingBatch::new(
    id=@update.TrainingBatchId::new(4UL),
    policy=cycle_actor(),
    items=[first_advantage.training_item(), second_advantage.training_item()],
    maximum_items=4,
    maximum_total_tokens=16,
    maximum_trainable_tokens=8,
  )
  cycle.prepare_training(
    @trainer.TrainingRequest::new(
      id=@trainer.TrainingRequestId::new(4UL),
      batch~,
    ),
  )
  assert_eq(cycle.group_count(), 2)
  assert_eq(cycle.rollout_count(), 2)
  assert_eq(cycle.state(), TrainerPrepared)
}

///|
test "group and terminal response identities are single-owner" {
  let request = cycle_request()
  let cycle = @cycle.UpdateCycle::new(cycle_manifest(), request)
  try cycle.add_group(request) catch {
    DuplicateGroup => ()
    _ => fail("unexpected duplicate-group error")
  } noraise {
    _ => fail("duplicate group was accepted")
  }
  let response = cycle_response_for(request, Complete, Completed)
  cycle.admit_rollout(response)
  try cycle.admit_rollout(response) catch {
    DuplicateRolloutResponse => ()
    _ => fail("unexpected duplicate-response error")
  } noraise {
    _ => fail("duplicate terminal response was accepted")
  }
}
