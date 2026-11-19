///|
pub(all) enum PublicationTransport {
  FullArtifactV1
  DeltaDeferred
} derive(Debug, Eq)

///|
pub(all) enum PublicationState {
  AwaitingReservation
  AwaitingTransport
  TransferringFullArtifact
  VerifyingArtifact
  AwaitingRankAcknowledgements
  AwaitingRecoveredRankAcknowledgements
  ReadyToCommit
  Committed
  TargetConflict
  Aborted
} derive(Debug, Eq)

///|
pub struct PublicationOwner {
  priv manifest : FullArtifactManifest
  priv chunks_seen : FixedArray[Bool]
  priv ranks_seen : FixedArray[Bool]
  priv mut chunk_count : Int32
  priv mut acknowledgement_count : Int32
  priv mut state : PublicationState
  priv mut conflicting_digest : @identity.Sha256Digest?
}

///|
pub fn PublicationOwner::new(manifest : FullArtifactManifest) -> Self {
  {
    chunks_seen: FixedArray::make(manifest.chunk_count(), false),
    ranks_seen: FixedArray::make(manifest.rollout_rank_count(), false),
    manifest,
    chunk_count: 0,
    acknowledgement_count: 0,
    state: AwaitingReservation,
    conflicting_digest: None,
  }
}

///|
fn PublicationOwner::require_state(
  self : Self,
  expected : PublicationState,
) -> Unit raise PublicationError {
  if self.state != expected {
    raise InvalidState(expected~, actual=self.state)
  }
}

///|
pub fn PublicationOwner::accept_reservation(
  self : Self,
  evidence : ReservationEvidence,
) -> Unit raise PublicationError {
  self.require_state(AwaitingReservation)
  if evidence.publication_id() != self.manifest.id() ||
    evidence.target() != self.manifest.target() ||
    evidence.artifact_digest() != self.manifest.artifact_digest() {
    raise ReservationMismatch
  }
  match evidence.outcome() {
    EmptyTargetReserved => self.state = AwaitingTransport
    ExistingCandidateResumed => {
      guard evidence.existing_digest() is Some(digest) &&
        digest == self.manifest.artifact_digest() else {
        raise ReservationMismatch
      }
      self.state = AwaitingRecoveredRankAcknowledgements
    }
    ExistingTargetRefused => {
      guard evidence.existing_digest() is Some(digest) &&
        digest != self.manifest.artifact_digest() else {
        raise ReservationMismatch
      }
      self.conflicting_digest = Some(digest)
      self.state = TargetConflict
    }
  }
}

///|
pub fn PublicationOwner::begin_transport(
  self : Self,
  transport : PublicationTransport,
) -> Unit raise PublicationError {
  self.require_state(AwaitingTransport)
  match transport {
    FullArtifactV1 => self.state = TransferringFullArtifact
    DeltaDeferred => raise DeltaTransportUnsupported
  }
}

///|
pub fn PublicationOwner::accept_chunk(
  self : Self,
  chunk : ArtifactChunkEvidence,
) -> Unit raise PublicationError {
  self.require_state(TransferringFullArtifact)
  if chunk.publication_id() != self.manifest.id() ||
    chunk.target() != self.manifest.target() {
    raise ManifestMismatch
  }
  let index = chunk.index()
  if index < 0 ||
    index >= self.chunks_seen.length() ||
    chunk.offset() != self.manifest.chunk_offset(index) ||
    chunk.length() != self.manifest.chunk_length(index) {
    raise ManifestMismatch
  }
  if self.chunks_seen[index] {
    raise DuplicateChunk
  }
  self.chunks_seen[index] = true
  self.chunk_count += 1
  if self.chunk_count == self.chunks_seen.length() {
    self.state = VerifyingArtifact
  }
}

///|
pub fn PublicationOwner::verify_artifact(
  self : Self,
  observed_digest : @identity.Sha256Digest,
) -> Unit raise PublicationError {
  self.require_state(VerifyingArtifact)
  if observed_digest != self.manifest.artifact_digest() {
    raise ArtifactDigestMismatch
  }
  self.state = AwaitingRankAcknowledgements
}

///|
pub fn PublicationOwner::accept_acknowledgement(
  self : Self,
  acknowledgement : RolloutRankAcknowledgement,
) -> Unit raise PublicationError {
  if self.state != AwaitingRankAcknowledgements &&
    self.state != AwaitingRecoveredRankAcknowledgements {
    raise InvalidState(expected=AwaitingRankAcknowledgements, actual=self.state)
  }
  if acknowledgement.publication_id() != self.manifest.id() ||
    acknowledgement.target() != self.manifest.target() ||
    acknowledgement.artifact_digest() != self.manifest.artifact_digest() {
    raise AcknowledgementMismatch
  }
  let rank = acknowledgement.rank()
  if rank < 0 || rank >= self.ranks_seen.length() {
    raise AcknowledgementMismatch
  }
  if self.ranks_seen[rank] {
    raise DuplicateRankAcknowledgement
  }
  self.ranks_seen[rank] = true
  self.acknowledgement_count += 1
  if self.acknowledgement_count == self.ranks_seen.length() {
    self.state = ReadyToCommit
  }
}

///|
pub fn PublicationOwner::commit(self : Self) -> Unit raise PublicationError {
  self.require_state(ReadyToCommit)
  self.state = Committed
}

///|
pub fn PublicationOwner::abort(self : Self) -> Unit raise PublicationError {
  match self.state {
    Committed | TargetConflict | Aborted =>
      raise InvalidState(expected=AwaitingReservation, actual=self.state)
    _ => self.state = Aborted
  }
}

///|
pub fn PublicationOwner::manifest(self : Self) -> FullArtifactManifest {
  self.manifest
}

///|
pub fn PublicationOwner::state(self : Self) -> PublicationState {
  self.state
}

///|
pub fn PublicationOwner::accepted_chunk_count(self : Self) -> Int32 {
  self.chunk_count
}

///|
pub fn PublicationOwner::acknowledgement_count(self : Self) -> Int32 {
  self.acknowledgement_count
}

///|
pub fn PublicationOwner::conflicting_digest(
  self : Self,
) -> @identity.Sha256Digest? {
  self.conflicting_digest
}
