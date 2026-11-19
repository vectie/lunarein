///|
pub(all) suberror PublicationError {
  InvalidPublicationId
  InvalidLimit
  InvalidChunkIndex
  InvalidRank
  ManifestMismatch
  ReservationMismatch
  DuplicateChunk
  ArtifactDigestMismatch
  DuplicateRankAcknowledgement
  AcknowledgementMismatch
  DeltaTransportUnsupported
  UnsupportedVersion
  InvalidState(expected~ : PublicationState, actual~ : PublicationState)
} derive(Debug, Eq)

///|
#valtype
pub struct PublicationId {
  priv value : UInt64
} derive(Debug, Eq)

///|
pub fn PublicationId::new(value : UInt64) -> Self raise PublicationError {
  if value == 0UL {
    raise InvalidPublicationId
  }
  { value, }
}

///|
pub fn PublicationId::value(self : Self) -> UInt64 {
  self.value
}

///|
pub struct FullArtifactManifest {
  priv version : @version.ProtocolVersion
  priv id : PublicationId
  priv candidate : @update.CandidatePolicy
  priv format : PolicyArtifactFormat
  priv total_bytes : Int64
  priv chunk_bytes : Int32
  priv chunk_count : Int32
  priv rollout_rank_count : Int32
}

///|
pub(all) enum PolicyArtifactFormat {
  SafetensorsV1
} derive(Debug, Eq)

///|
pub fn FullArtifactManifest::new(
  id~ : PublicationId,
  candidate~ : @update.CandidatePolicy,
  total_bytes~ : Int64,
  chunk_bytes~ : Int32,
  maximum_chunk_bytes~ : Int32,
  rollout_rank_count~ : Int32,
  maximum_artifact_bytes~ : Int64,
  maximum_chunks~ : Int32,
  maximum_rollout_ranks~ : Int32,
) -> Self raise PublicationError {
  if maximum_artifact_bytes <= 0L ||
    maximum_chunks <= 0 ||
    maximum_chunks > 1048576 ||
    maximum_rollout_ranks <= 0 ||
    maximum_rollout_ranks > 65536 ||
    total_bytes <= 0L ||
    total_bytes > maximum_artifact_bytes ||
    chunk_bytes <= 0 ||
    maximum_chunk_bytes <= 0 ||
    maximum_chunk_bytes > 1073741824 ||
    chunk_bytes > maximum_chunk_bytes ||
    rollout_rank_count <= 0 ||
    rollout_rank_count > maximum_rollout_ranks {
    raise InvalidLimit
  }
  let chunk_width = chunk_bytes.to_int64()
  let count64 = (total_bytes - 1L) / chunk_width + 1L
  if count64 > maximum_chunks.to_int64() {
    raise InvalidLimit
  }
  {
    version: @version.ProtocolVersion::v1(),
    id,
    candidate,
    format: SafetensorsV1,
    total_bytes,
    chunk_bytes,
    chunk_count: count64.to_int(),
    rollout_rank_count,
  }
}

///|
pub fn FullArtifactManifest::new_versioned(
  version~ : @version.ProtocolVersion,
  id~ : PublicationId,
  candidate~ : @update.CandidatePolicy,
  total_bytes~ : Int64,
  chunk_bytes~ : Int32,
  maximum_chunk_bytes~ : Int32,
  rollout_rank_count~ : Int32,
  maximum_artifact_bytes~ : Int64,
  maximum_chunks~ : Int32,
  maximum_rollout_ranks~ : Int32,
) -> Self raise PublicationError {
  if !version.is_exact(@version.ProtocolVersion::v1()) {
    raise UnsupportedVersion
  }
  FullArtifactManifest::new(
    id~,
    candidate~,
    total_bytes~,
    chunk_bytes~,
    maximum_chunk_bytes~,
    rollout_rank_count~,
    maximum_artifact_bytes~,
    maximum_chunks~,
    maximum_rollout_ranks~,
  )
}

///|
pub fn FullArtifactManifest::version(self : Self) -> @version.ProtocolVersion {
  self.version
}

///|
pub fn FullArtifactManifest::format(self : Self) -> PolicyArtifactFormat {
  self.format
}

///|
pub fn FullArtifactManifest::id(self : Self) -> PublicationId {
  self.id
}

///|
pub fn FullArtifactManifest::candidate(self : Self) -> @update.CandidatePolicy {
  self.candidate
}

///|
pub fn FullArtifactManifest::parent(self : Self) -> @identity.PolicyGeneration {
  self.candidate.parent()
}

///|
pub fn FullArtifactManifest::target(self : Self) -> @identity.PolicyGeneration {
  self.candidate.target()
}

///|
pub fn FullArtifactManifest::artifact_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.candidate.artifact_digest()
}

///|
pub fn FullArtifactManifest::tensor_vocabulary_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.candidate.tensor_vocabulary_digest()
}

///|
pub fn FullArtifactManifest::total_bytes(self : Self) -> Int64 {
  self.total_bytes
}

///|
pub fn FullArtifactManifest::chunk_bytes(self : Self) -> Int32 {
  self.chunk_bytes
}

///|
pub fn FullArtifactManifest::chunk_count(self : Self) -> Int32 {
  self.chunk_count
}

///|
pub fn FullArtifactManifest::rollout_rank_count(self : Self) -> Int32 {
  self.rollout_rank_count
}

///|
pub fn FullArtifactManifest::chunk_offset(
  self : Self,
  index : Int32,
) -> Int64 raise PublicationError {
  if index < 0 || index >= self.chunk_count {
    raise InvalidChunkIndex
  }
  index.to_int64() * self.chunk_bytes.to_int64()
}

///|
pub fn FullArtifactManifest::chunk_length(
  self : Self,
  index : Int32,
) -> Int32 raise PublicationError {
  let remaining = self.total_bytes - self.chunk_offset(index)
  if remaining < self.chunk_bytes.to_int64() {
    remaining.to_int()
  } else {
    self.chunk_bytes
  }
}

///|
pub struct ArtifactChunkEvidence {
  priv publication_id : PublicationId
  priv target : @identity.PolicyGeneration
  priv index : Int32
  priv offset : Int64
  priv length : Int32
  priv chunk_digest : @identity.Sha256Digest
}

///|
pub fn ArtifactChunkEvidence::new(
  manifest~ : FullArtifactManifest,
  index~ : Int32,
  chunk_digest~ : @identity.Sha256Digest,
) -> Self raise PublicationError {
  {
    publication_id: manifest.id(),
    target: manifest.target(),
    index,
    offset: manifest.chunk_offset(index),
    length: manifest.chunk_length(index),
    chunk_digest,
  }
}

///|
pub fn ArtifactChunkEvidence::publication_id(self : Self) -> PublicationId {
  self.publication_id
}

///|
pub fn ArtifactChunkEvidence::target(self : Self) -> @identity.PolicyGeneration {
  self.target
}

///|
pub fn ArtifactChunkEvidence::index(self : Self) -> Int32 {
  self.index
}

///|
pub fn ArtifactChunkEvidence::offset(self : Self) -> Int64 {
  self.offset
}

///|
pub fn ArtifactChunkEvidence::length(self : Self) -> Int32 {
  self.length
}

///|
pub fn ArtifactChunkEvidence::chunk_digest(
  self : Self,
) -> @identity.Sha256Digest {
  self.chunk_digest
}
