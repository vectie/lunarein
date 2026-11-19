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
fn candidate() -> @update.CandidatePolicy raise {
  @update.CandidatePolicy::new(
    parent=parent_policy(),
    target=target_policy(),
    artifact_digest=target_policy().actor(),
    tensor_vocabulary_digest=digest(
      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ),
  )
}

///|
fn manifest_with_id(id : UInt64) -> @publication.FullArtifactManifest raise {
  @publication.FullArtifactManifest::new(
    id=@publication.PublicationId::new(id),
    candidate=candidate(),
    total_bytes=10L,
    chunk_bytes=4,
    maximum_chunk_bytes=8,
    rollout_rank_count=2,
    maximum_artifact_bytes=1024L,
    maximum_chunks=16,
    maximum_rollout_ranks=8,
  )
}

///|
fn chunk_digest(index : Int32) -> @identity.Sha256Digest raise {
  match index {
    0 =>
      digest("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
    1 =>
      digest("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
    _ =>
      digest("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
  }
}

///|
test "publication rejects an unsupported protocol version" {
  let version = @version.ProtocolVersion::new(major=2, minor=0)
  try
    @publication.FullArtifactManifest::new_versioned(
      version~,
      id=@publication.PublicationId::new(4UL),
      candidate=candidate(),
      total_bytes=10L,
      chunk_bytes=4,
      maximum_chunk_bytes=8,
      rollout_rank_count=2,
      maximum_artifact_bytes=1024L,
      maximum_chunks=16,
      maximum_rollout_ranks=8,
    )
  catch {
    @publication.UnsupportedVersion => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected unsupported-version rejection")
  }
}

///|
test "full publication requires every chunk and rollout rank" {
  let manifest = manifest_with_id(4UL)
  assert_eq(manifest.version(), @version.ProtocolVersion::v1())
  assert_eq(manifest.parent(), parent_policy())
  assert_eq(manifest.target(), target_policy())
  assert_eq(manifest.format(), SafetensorsV1)
  assert_eq(manifest.chunk_count(), 3)
  assert_eq(manifest.chunk_offset(2), 8L)
  assert_eq(manifest.chunk_length(2), 2)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(@publication.ReservationEvidence::reserved(manifest))
  owner.begin_transport(FullArtifactV1)
  for index in 0..<manifest.chunk_count() {
    owner.accept_chunk(
      @publication.ArtifactChunkEvidence::new(
        manifest~,
        index~,
        chunk_digest=chunk_digest(index),
      ),
    )
  }
  assert_eq(owner.state(), VerifyingArtifact)
  owner.verify_artifact(manifest.artifact_digest())
  owner.accept_acknowledgement(
    @publication.RolloutRankAcknowledgement::new(
      manifest~,
      rank=1,
      observed_artifact_digest=manifest.artifact_digest(),
    ),
  )
  assert_eq(owner.state(), AwaitingRankAcknowledgements)
  owner.accept_acknowledgement(
    @publication.RolloutRankAcknowledgement::new(
      manifest~,
      rank=0,
      observed_artifact_digest=manifest.artifact_digest(),
    ),
  )
  assert_eq(owner.state(), ReadyToCommit)
  owner.commit()
  assert_eq(owner.state(), Committed)
  assert_eq(owner.accepted_chunk_count(), 3)
  assert_eq(owner.acknowledgement_count(), 2)
}

///|
test "existing target is a terminal no-overwrite conflict" {
  let manifest = manifest_with_id(4UL)
  let existing = chunk_digest(0)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(
    @publication.ReservationEvidence::existing(manifest, existing),
  )
  assert_eq(owner.state(), TargetConflict)
  assert_eq(owner.conflicting_digest(), Some(existing))
  try owner.begin_transport(FullArtifactV1) catch {
    InvalidState(expected=_, actual=_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected no-overwrite terminal state")
  }
  assert_eq(owner.accepted_chunk_count(), 0)
}

///|
test "retry resumes an exact candidate without retransmission" {
  let manifest = manifest_with_id(4UL)
  let reservation = @publication.ReservationEvidence::existing(
    manifest,
    manifest.artifact_digest(),
  )
  assert_eq(reservation.outcome(), ExistingCandidateResumed)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(reservation)
  assert_eq(owner.state(), AwaitingRecoveredRankAcknowledgements)
  assert_eq(owner.accepted_chunk_count(), 0)
  try owner.begin_transport(FullArtifactV1) catch {
    InvalidState(expected=_, actual=_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("recovered candidate allowed retransmission")
  }
  for rank in 0..<manifest.rollout_rank_count() {
    owner.accept_acknowledgement(
      @publication.RolloutRankAcknowledgement::new(
        manifest~,
        rank~,
        observed_artifact_digest=manifest.artifact_digest(),
      ),
    )
  }
  assert_eq(owner.state(), ReadyToCommit)
  owner.commit()
  assert_eq(owner.state(), Committed)
  assert_eq(owner.accepted_chunk_count(), 0)
  assert_eq(owner.acknowledgement_count(), 2)
}

///|
test "delta transport is explicitly deferred without mutation" {
  let manifest = manifest_with_id(4UL)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(@publication.ReservationEvidence::reserved(manifest))
  try owner.begin_transport(DeltaDeferred) catch {
    DeltaTransportUnsupported => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected deferred delta rejection")
  }
  assert_eq(owner.state(), AwaitingTransport)
}

///|
test "duplicate chunk fails before count or state mutation" {
  let manifest = manifest_with_id(4UL)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(@publication.ReservationEvidence::reserved(manifest))
  owner.begin_transport(FullArtifactV1)
  let chunk = @publication.ArtifactChunkEvidence::new(
    manifest~,
    index=0,
    chunk_digest=chunk_digest(0),
  )
  owner.accept_chunk(chunk)
  try owner.accept_chunk(chunk) catch {
    DuplicateChunk => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected duplicate rejection")
  }
  assert_eq(owner.accepted_chunk_count(), 1)
  assert_eq(owner.state(), TransferringFullArtifact)
}

///|
test "full digest mismatch cannot advance to acknowledgements" {
  let manifest = manifest_with_id(4UL)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(@publication.ReservationEvidence::reserved(manifest))
  owner.begin_transport(FullArtifactV1)
  for index in 0..<manifest.chunk_count() {
    owner.accept_chunk(
      @publication.ArtifactChunkEvidence::new(
        manifest~,
        index~,
        chunk_digest=chunk_digest(index),
      ),
    )
  }
  try owner.verify_artifact(chunk_digest(0)) catch {
    @publication.ArtifactDigestMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected artifact mismatch")
  }
  assert_eq(owner.state(), VerifyingArtifact)
}

///|
test "acknowledgement from another publication is rejected" {
  let manifest = manifest_with_id(4UL)
  let other = manifest_with_id(5UL)
  let owner = @publication.PublicationOwner::new(manifest)
  owner.accept_reservation(@publication.ReservationEvidence::reserved(manifest))
  owner.begin_transport(FullArtifactV1)
  for index in 0..<manifest.chunk_count() {
    owner.accept_chunk(
      @publication.ArtifactChunkEvidence::new(
        manifest~,
        index~,
        chunk_digest=chunk_digest(index),
      ),
    )
  }
  owner.verify_artifact(manifest.artifact_digest())
  try
    owner.accept_acknowledgement(
      @publication.RolloutRankAcknowledgement::new(
        manifest=other,
        rank=0,
        observed_artifact_digest=other.artifact_digest(),
      ),
    )
  catch {
    AcknowledgementMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected acknowledgement mismatch")
  }
  assert_eq(owner.acknowledgement_count(), 0)
  assert_eq(owner.state(), AwaitingRankAcknowledgements)
}

///|
test "rank cannot acknowledge an unobserved artifact digest" {
  let manifest = manifest_with_id(4UL)
  try
    @publication.RolloutRankAcknowledgement::new(
      manifest~,
      rank=0,
      observed_artifact_digest=chunk_digest(0),
    )
  catch {
    @publication.ArtifactDigestMismatch => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected observed-digest rejection")
  }
}
