///|
pub(all) enum ReservationOutcome {
  EmptyTargetReserved
  ExistingCandidateResumed
  ExistingTargetRefused
} derive(Debug, Eq)

///|
pub struct ReservationEvidence {
  priv publication_id : PublicationId
  priv target : @identity.PolicyGeneration
  priv artifact_digest : @identity.Sha256Digest
  priv outcome : ReservationOutcome
  priv existing_digest : @identity.Sha256Digest?
}

///|
pub fn ReservationEvidence::reserved(manifest : FullArtifactManifest) -> Self {
  {
    publication_id: manifest.id(),
    target: manifest.target(),
    artifact_digest: manifest.artifact_digest(),
    outcome: EmptyTargetReserved,
    existing_digest: None,
  }
}

///|
pub fn ReservationEvidence::existing(
  manifest : FullArtifactManifest,
  existing_digest : @identity.Sha256Digest,
) -> Self {
  let outcome = if existing_digest == manifest.artifact_digest() {
    ExistingCandidateResumed
  } else {
    ExistingTargetRefused
  }
  {
    publication_id: manifest.id(),
    target: manifest.target(),
    artifact_digest: manifest.artifact_digest(),
    outcome,
    existing_digest: Some(existing_digest),
  }
}

///|
pub fn ReservationEvidence::publication_id(self : Self) -> PublicationId {
  self.publication_id
}

///|
pub fn ReservationEvidence::target(self : Self) -> @identity.PolicyGeneration {
  self.target
}

///|
pub fn ReservationEvidence::artifact_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.artifact_digest
}

///|
pub fn ReservationEvidence::outcome(self : Self) -> ReservationOutcome {
  self.outcome
}

///|
pub fn ReservationEvidence::existing_digest(
  self : Self,
) -> @identity.Sha256Digest? {
  self.existing_digest
}

///|
pub struct RolloutRankAcknowledgement {
  priv publication_id : PublicationId
  priv target : @identity.PolicyGeneration
  priv artifact_digest : @identity.Sha256Digest
  priv rank : Int32
}

///|
pub fn RolloutRankAcknowledgement::new(
  manifest~ : FullArtifactManifest,
  rank~ : Int32,
  observed_artifact_digest~ : @identity.Sha256Digest,
) -> Self raise PublicationError {
  if rank < 0 || rank >= manifest.rollout_rank_count() {
    raise InvalidRank
  }
  if observed_artifact_digest != manifest.artifact_digest() {
    raise ArtifactDigestMismatch
  }
  {
    publication_id: manifest.id(),
    target: manifest.target(),
    artifact_digest: observed_artifact_digest,
    rank,
  }
}

///|
pub fn RolloutRankAcknowledgement::publication_id(self : Self) -> PublicationId {
  self.publication_id
}

///|
pub fn RolloutRankAcknowledgement::target(
  self : Self,
) -> @identity.PolicyGeneration {
  self.target
}

///|
pub fn RolloutRankAcknowledgement::artifact_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.artifact_digest
}

///|
pub fn RolloutRankAcknowledgement::rank(self : Self) -> Int32 {
  self.rank
}
