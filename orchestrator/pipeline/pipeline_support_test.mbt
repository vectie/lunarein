///|
fn pipeline_digest(byte : String) -> @identity.Sha256Digest {
  try! @identity.Sha256Digest::parse(byte.repeat(64))
}

///|
fn pipeline_policies() -> (
  @identity.PolicyGeneration,
  @identity.PolicyGeneration,
  @identity.PolicyGeneration,
) {
  let first = @identity.PolicyGeneration::initial(pipeline_digest("a"))
  let second = try! @identity.PolicyGeneration::new(
    sequence=2UL,
    actor=pipeline_digest("b"),
    parent_actor=Some(first.actor()),
  )
  let third = try! @identity.PolicyGeneration::new(
    sequence=3UL,
    actor=pipeline_digest("c"),
    parent_actor=Some(second.actor()),
  )
  (first, second, third)
}

///|
fn pipeline_manifest(
  actor : @identity.PolicyGeneration,
  dataset_byte : String,
  pending_updates : UInt64,
) -> @experiment.ExperimentManifest {
  @experiment.ExperimentManifest::new(
    identity=@experiment.ExperimentIdentity::new(pipeline_digest("9")),
    actor~,
    dataset=@experiment.DatasetIdentity::new(pipeline_digest(dataset_byte)),
    reward_policy=@experiment.RewardPolicyIdentity::new(pipeline_digest("7")),
    tokenizer=@experiment.TokenizerIdentity::new(pipeline_digest("6")),
    algorithm=@experiment.AlgorithmIdentity::new(
      pipeline_digest("5"),
      Reinforce,
    ),
    limits=@experiment.ExperimentLimits::new(
      concurrent_groups=try! @experiment.ConcurrentGroupCapacity::new(2UL),
      rollouts_per_group=try! @experiment.RolloutsPerGroupCapacity::new(4UL),
      prompt_tokens=try! @experiment.PromptTokenCapacity::new(8UL),
      response_tokens=try! @experiment.ResponseTokenCapacity::new(6UL),
      pending_updates=try! @experiment.PendingUpdateCapacity::new(
        pending_updates,
      ),
    ),
  )
}

///|
fn pipeline_request(
  manifest : @experiment.ExperimentManifest,
  rollout_value : UInt64,
) -> @rollout.RolloutGroupRequest {
  let sampling = @rollout.SamplingIdentity::new(
    plan_digest=pipeline_digest("4"),
    seed=rollout_value,
  )
  let slot = @rollout.RolloutSlot::new(
    rollout_id=try! @identity.RolloutId::new(rollout_value),
    sampling~,
  )
  try! @rollout.RolloutGroupRequest::new(
    protocol_version=@version.ProtocolVersion::v1(),
    request_id=@rollout.RolloutRequestId::new(pipeline_digest("3")),
    experiment=manifest.identity(),
    dataset=manifest.dataset(),
    group_id=try! @identity.GroupId::new(rollout_value),
    actor=manifest.actor(),
    tokenizer=manifest.tokenizer(),
    limits=try! @rollout.RolloutLimits::new(
      maximum_rollouts=1,
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
fn pipeline_response(
  request : @rollout.RolloutGroupRequest,
) -> @rollout.RolloutResponse {
  let slot = try! request.slot_at(0)
  let model = try! @trajectory.RolloutToken::model(
    token_id=5,
    model_logprob=-1.0,
    sampling_logprob=-0.8,
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
    terminal=Completed,
    maximum_prompt_tokens=8,
    maximum_response_tokens=6,
    maximum_token_id=31,
  )
  try! @rollout.RolloutResponse::new(
    protocol_version=request.protocol_version(),
    request_id=request.request_id(),
    tokenizer=request.tokenizer(),
    sampling=slot.sampling(),
    trajectory~,
    terminal=Complete,
    expected_request=request,
  )
}

///|
fn pipeline_advantage(
  trajectory : @trajectory.Trajectory,
) -> @advantage.AdvantageEvidence {
  let source = @reward.RewardSourceId::new(pipeline_digest("7"))
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
    algorithm=@experiment.AlgorithmIdentity::new(
      pipeline_digest("5"),
      Reinforce,
    ),
  )
}

///|
fn pipeline_make_ready(
  cycle : @cycle.UpdateCycle,
  request : @rollout.RolloutGroupRequest,
) -> (@trajectory.Trajectory, @advantage.AdvantageEvidence) {
  let response = pipeline_response(request)
  let trajectory = response.trajectory()
  let advantage = pipeline_advantage(trajectory)
  try! cycle.admit_rollout(response)
  try! cycle.seal_rollouts()
  try! cycle.accept_advantage(advantage)
  (trajectory, advantage)
}

///|
fn pipeline_training_request(
  advantage : @advantage.AdvantageEvidence,
) -> @trainer.TrainingRequest {
  let item = try! advantage.training_item()
  let batch = try! @update.TrainingBatch::new(
    id=try! @update.TrainingBatchId::new(1UL),
    policy=advantage.policy(),
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
fn pipeline_committed_publication(
  candidate : @update.CandidatePolicy,
) -> @publication.PublicationOwner {
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
  try! owner.accept_reservation(
    @publication.ReservationEvidence::reserved(manifest),
  )
  try! owner.begin_transport(FullArtifactV1)
  try! owner.accept_chunk(
    @publication.ArtifactChunkEvidence::new(
      manifest~,
      index=0,
      chunk_digest=pipeline_digest("0"),
    ),
  )
  try! owner.verify_artifact(manifest.artifact_digest())
  try! owner.accept_acknowledgement(
    @publication.RolloutRankAcknowledgement::new(
      manifest~,
      rank=0,
      observed_artifact_digest=manifest.artifact_digest(),
    ),
  )
  try! owner.commit()
  owner
}

///|
fn pipeline_complete(
  cycle : @cycle.UpdateCycle,
  request : @rollout.RolloutGroupRequest,
  successor : @identity.PolicyGeneration,
) -> Unit {
  let (_, advantage) = pipeline_make_ready(cycle, request)
  let training = pipeline_training_request(advantage)
  try! cycle.prepare_training(training)
  try! cycle.dispatch_training()
  let candidate = try! @update.CandidatePolicy::new(
    parent=cycle.policy(),
    target=successor,
    artifact_digest=successor.actor(),
    tensor_vocabulary_digest=pipeline_digest("f"),
  )
  let evidence = try! @update.OptimizerStepEvidence::new(
    step_id=try! @update.OptimizerStepId::new(1UL),
    batch=training.batch(),
    candidate~,
    optimizer_state_digest=pipeline_digest("e"),
    trained_token_count=1,
    mean_loss=0.25,
  )
  try! cycle.accept_trainer_result(
    @trainer.TrainerStepResult::new(request=training, evidence~, candidate~),
  )
  try! cycle.accept_committed_publication(
    pipeline_committed_publication(candidate),
  )
  try! cycle.finish()
}
